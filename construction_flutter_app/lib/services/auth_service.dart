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

  /// Flow A: Register a new company and create the first Admin user atomically.
  Future<UserCredential> registerCompanyAndAdmin({
    required String companyName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final uid = cred.user!.uid;

      final companyRef = _db.collection('companies').doc();
      final userRef = _db.collection('users').doc(uid);

      final batch = _db.batch();
      batch.set(companyRef, {
        'name': companyName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
        'isActive': true,
      });

      final user = UserModel(
        uid: uid,
        name: adminName.trim(),
        email: email.trim(),
        role: UserRole.admin,
        companyId: companyRef.id,
        assignedProjects: [],
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      batch.set(userRef, user.toJson());

      await batch.commit();
      return cred;
    } catch (e) {
      throw Exception('Company registration failed: ${e.toString().split(']').last}');
    }
  }

  /// Flow B: Join an existing company using an invite code.
  Future<UserCredential> joinCompanyWithCode({
    required String inviteCode,
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final code = inviteCode.trim().toUpperCase();

      // 1. Validate invite code before creating auth credentials
      final codeRef = _db.collection('inviteCodes').doc(code);
      final codeSnap = await codeRef.get();

      if (!codeSnap.exists) {
        throw Exception('Invalid invite code. Please check and try again.');
      }

      final codeData = codeSnap.data()!;
      final isActive = codeData['isActive'] as bool? ?? true;
      final maxUses = codeData['maxUses'] as int? ?? 1;
      final usesSoFar = codeData['usesSoFar'] as int? ?? 0;
      final companyId = codeData['companyId'] as String? ?? '';
      final roleStr = codeData['role'] as String? ?? 'engineer';
      final expiresAtTs = codeData['expiresAt'] as Timestamp?;

      if (!isActive || usesSoFar >= maxUses) {
        throw Exception('This invite code has already reached its maximum uses or is inactive.');
      }

      if (expiresAtTs != null && DateTime.now().isAfter(expiresAtTs.toDate())) {
        throw Exception('This invite code has expired.');
      }

      final targetRole = UserRole.values.firstWhere(
        (r) => r.name == roleStr,
        orElse: () => UserRole.engineer,
      );

      // 2. Create Auth user
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final uid = cred.user!.uid;

      // 3. Atomically create user profile & consume code
      final userRef = _db.collection('users').doc(uid);
      final newUses = usesSoFar + 1;

      final batch = _db.batch();
      final user = UserModel(
        uid: uid,
        name: name.trim(),
        email: email.trim(),
        role: targetRole,
        companyId: companyId,
        assignedProjects: [],
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      batch.set(userRef, user.toJson());

      batch.update(codeRef, {
        'usesSoFar': newUses,
        'isActive': newUses < maxUses,
      });

      await batch.commit();
      return cred;
    } catch (e) {
      throw Exception('Joining company failed: ${e.toString().split(']').last}');
    }
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
      final userRef = _db.collection('users').doc(user.uid);

      final batch = _db.batch();
      batch.set(companyRef, {
        'name': companyName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'isActive': true,
      });

      final userModel = UserModel(
        uid: user.uid,
        name: name.trim(),
        email: user.email ?? '',
        role: UserRole.admin,
        companyId: companyRef.id,
        assignedProjects: [],
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      batch.set(userRef, userModel.toJson());

      await batch.commit();
    } else {
      if (inviteCode == null || inviteCode.trim().isEmpty) {
        throw Exception('Invite code is required');
      }
      final code = inviteCode.trim().toUpperCase();
      final codeRef = _db.collection('inviteCodes').doc(code);
      final codeSnap = await codeRef.get();

      if (!codeSnap.exists) {
        throw Exception('Invalid invite code. Please check and try again.');
      }

      final codeData = codeSnap.data()!;
      final isActive = codeData['isActive'] as bool? ?? true;
      final maxUses = codeData['maxUses'] as int? ?? 1;
      final usesSoFar = codeData['usesSoFar'] as int? ?? 0;
      final companyId = codeData['companyId'] as String? ?? '';
      final roleStr = codeData['role'] as String? ?? 'engineer';
      final expiresAtTs = codeData['expiresAt'] as Timestamp?;

      if (!isActive || usesSoFar >= maxUses) {
        throw Exception('This invite code has expired or reached its maximum uses.');
      }

      if (expiresAtTs != null && DateTime.now().isAfter(expiresAtTs.toDate())) {
        throw Exception('This invite code has expired.');
      }

      final targetRole = UserRole.values.firstWhere(
        (r) => r.name == roleStr,
        orElse: () => UserRole.engineer,
      );

      final userRef = _db.collection('users').doc(user.uid);
      final newUses = usesSoFar + 1;

      final batch = _db.batch();
      final userModel = UserModel(
        uid: user.uid,
        name: name.trim(),
        email: user.email ?? '',
        role: targetRole,
        companyId: companyId,
        assignedProjects: [],
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      batch.set(userRef, userModel.toJson());

      batch.update(codeRef, {
        'usesSoFar': newUses,
        'isActive': newUses < maxUses,
      });

      await batch.commit();
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
