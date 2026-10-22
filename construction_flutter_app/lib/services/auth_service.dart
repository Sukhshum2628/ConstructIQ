import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../providers/auth_provider.dart';

class AuthService {
  final Ref? _ref;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AuthService([this._ref]);

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      // Update lastLogin on success
      await _db.collection('users').doc(cred.user!.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
      return cred;
    } catch (e) {
      throw Exception('Login failed: ${e.toString().split(']').last}');
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    debugPrint("DEBUG: [1] Attempting Google Sign-In (kIsWeb: $kIsWeb)...");
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // Web flow: Use Firebase JS popup directly
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        
        try {
          userCredential = await _auth.signInWithPopup(googleProvider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked' || e.code == 'cancelled-popup-request') {
            debugPrint("DEBUG: Popup blocked or cancelled, falling back to redirect flow...");
            await _auth.signInWithRedirect(googleProvider);
            userCredential = await _auth.getRedirectResult();
          } else {
            rethrow;
          }
        }
      } else {
        // Mobile flow: existing google_sign_in package flow
        final GoogleSignInAccount? googleUser = await GoogleSignIn(
          serverClientId: AppConstants.googleClientId,
        ).signIn();
        if (googleUser == null) {
          debugPrint("DEBUG: [2] Google sign in was aborted by user.");
          return null;
        }
        debugPrint("DEBUG: [3] Google User found: ${googleUser.email}");

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth.signInWithCredential(credential);
      }

      debugPrint("DEBUG: Firebase Auth Success - UID: ${userCredential.user?.uid}");
      
      // Update lastLogin if user exists, otherwise router handles routing to /role-selection
      final user = userCredential.user;
      if (user != null) {
        final userDoc = await _db.collection('users').doc(user.uid).get();
        debugPrint("DEBUG: Firestore Doc Exists: ${userDoc.exists}");
        if (userDoc.exists) {
          await _db.collection('users').doc(user.uid).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      }
      
      return userCredential;
    } catch (e) {
      debugPrint("DEBUG: [ERROR] Google Sign-In failed: $e");
      String message = 'Google Sign-In failed: $e';
      
      if (e.toString().contains('unauthorized-domain') || e.toString().contains('auth/unauthorized-domain')) {
        message = 'UNAUTHORIZED DOMAIN: Add this web domain to Firebase Console -> Authentication -> Settings -> Authorized Domains.';
      } else if (e.toString().contains('DEVELOPER_ERROR') || e.toString().contains('code 10')) {
        message = 'CONFIGURATION ERROR: Google Sign-In is misconfigured. Please ensure your SHA-1 fingerprint (from signingReport) is added to the Firebase Console.';
      } else if (e.toString().contains('network_error')) {
        message = 'NETWORK ERROR: Check your internet connection and try again.';
      }

      throw Exception(message);
    }
  }

  /// Sign in as a demo user using Firebase Anonymous Authentication seeded with local data.
  Future<UserCredential> signInAsDemo() async {
    try {
      final credential = await _auth.signInAnonymously();
      _ref?.read(isDemoModeProvider.notifier).state = true;
      return credential;
    } catch (e) {
      throw Exception('Demo sign-in failed: $e');
    }
  }

  /// Cleanly exit demo mode, deleting the anonymous user account so accounts don't accumulate.
  Future<void> signOutDemo() async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.delete();
      } catch (e) {
        debugPrint('Note: Error deleting anonymous demo user: $e');
      }
    }
    _ref?.read(isDemoModeProvider.notifier).state = false;
    await logout();
  }

  /// Flow A: Register a new company and create the first Admin user atomically via Cloud Functions.
  Future<UserCredential> registerCompanyAndAdmin({
    required String companyName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    try {
      // Step 1: Create Firebase Auth user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final uid = credential.user!.uid;

      // Step 2: Create company document
      final companyRef = _db.collection('companies').doc();
      await companyRef.set({
        'name': companyName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'isActive': true,
      });

      // Step 3: Create user document with pendingCompanyId
      // DO NOT write role or companyId — Cloud Function handles this server-side
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': adminName.trim(),
        'email': email.trim(),
        'pendingCompanyId': companyRef.id,
        'assignedProjects': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // Step 4: Wait for Cloud Function to assign role and companyId
      await _waitForRegistrationComplete(uid);

      // Step 5: Force token refresh to get new custom claims
      await credential.user!.getIdToken(true);

      return credential;
    } catch (e) {
      throw Exception('Company registration failed: ${e.toString().split(']').last}');
    }
  }

  /// Flow B: Join an existing company using an invite code via Cloud Functions.
  Future<UserCredential> joinCompanyWithCode({
    required String inviteCode,
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final code = inviteCode.trim().toUpperCase();

      // Step 1: Pre-validate code exists and is active (UX check only)
      final codeDoc = await _db.collection('inviteCodes').doc(code).get();

      if (!codeDoc.exists || codeDoc.data()?['isActive'] == false) {
        throw Exception('Invalid or inactive invite code');
      }

      // Step 2: Create Firebase Auth user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final uid = credential.user!.uid;

      // Step 3: Create user document with pendingInviteCode
      // Cloud Function will validate the code and assign role/companyId server-side
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name.trim(),
        'email': email.trim(),
        'pendingInviteCode': code,
        'assignedProjects': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // Step 4: Wait for Cloud Function to complete
      await _waitForRegistrationComplete(uid);

      // Step 5: Force token refresh to get new custom claims
      await credential.user!.getIdToken(true);

      return credential;
    } catch (e) {
      throw Exception('Joining company failed: ${e.toString().split(']').last}');
    }
  }

  /// Helper to wait for the server-side Cloud Function to complete role & company assignment.
  Future<void> _waitForRegistrationComplete(String uid) async {
    final completer = Completer<void>();
    StreamSubscription? subscription;

    final timeout = Timer(const Duration(seconds: 15), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Registration timed out — please try again')
        );
      }
    });

    subscription = _db.collection('users').doc(uid).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;

      if (data['registrationStatus'] == 'complete' || data['role'] != null) {
        timeout.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) completer.complete();
      } else if (data['registrationError'] != null) {
        timeout.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            Exception(data['registrationError'])
          );
        }
      }
    });

    return completer.future;
  }

  /// Onboarding flow for Google Sign-In or users with incomplete profiles.
  Future<void> completeUserProfileWithCompany({
    required String name,
    required bool isCreatingCompany,
    String? companyName,
    String? inviteCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    if (isCreatingCompany) {
      if (companyName == null || companyName.trim().isEmpty) {
        throw Exception('Company name is required');
      }

      final companyRef = _db.collection('companies').doc();
      await companyRef.set({
        'name': companyName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'isActive': true,
      });

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name.trim(),
        'email': user.email ?? '',
        'pendingCompanyId': companyRef.id,
        'assignedProjects': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      await _waitForRegistrationComplete(user.uid);
      await user.getIdToken(true);
    } else {
      if (inviteCode == null || inviteCode.trim().isEmpty) {
        throw Exception('Invite code is required');
      }
      final code = inviteCode.trim().toUpperCase();
      final codeDoc = await _db.collection('inviteCodes').doc(code).get();

      if (!codeDoc.exists || codeDoc.data()?['isActive'] == false) {
        throw Exception('Invalid or inactive invite code');
      }

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name.trim(),
        'email': user.email ?? '',
        'pendingInviteCode': code,
        'assignedProjects': [],
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      await _waitForRegistrationComplete(user.uid);
      await user.getIdToken(true);
    }
  }

  // Legacy compatibility method redirecting to completeUserProfileWithCompany
  @Deprecated('Use registerCompanyAndAdmin or joinCompanyWithCode instead')
  Future<UserCredential> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    required String accessKey,
  }) async {
    // If accessKey is formatted like an invite code, try joinCompanyWithCode
    return joinCompanyWithCode(
      inviteCode: accessKey,
      name: name,
      email: email,
      password: password,
    );
  }

  @Deprecated('Use completeUserProfileWithCompany instead')
  Future<void> completeUserProfile({
    required String name,
    required UserRole role,
    required String accessKey,
  }) async {
    return completeUserProfileWithCompany(
      name: name,
      isCreatingCompany: false,
      inviteCode: accessKey,
    );
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      // Clear the Google session cache so account switching is fully refreshed.
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      try {
        await googleSignIn.disconnect();
      } catch (_) {
        // Ignore disconnect errors when there is no active Google session.
      }
    } catch (e) {
      throw Exception('Logout failed: $e');
    }
  }

  // Alias for compatibility
  Future<void> signOut() => logout();

  Future<UserModel?> getCurrentUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;
      return UserModel.fromJson(doc.data()!);
    } catch (e) {
      throw Exception('Failed to fetch user data: $e');
    }
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? designation,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (designation != null) updates['designation'] = designation;

    if (updates.isEmpty) return;

    try {
      await _db.collection('users').doc(user.uid).update(updates);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }
}
