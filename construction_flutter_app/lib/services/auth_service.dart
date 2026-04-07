import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  Future<UserCredential> signInWithGoogle() async {
    debugPrint("DEBUG: [1] Attempting Google Sign-In...");
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        serverClientId: '999147799724-ai5qed4irvuve5q0bp7s0ugclhq4s7i8.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) {
        debugPrint("DEBUG: [2] Google sign in was aborted by user.");
        throw Exception('Google sign in aborted');
      }
      debugPrint("DEBUG: [3] Google User found: ${googleUser.email}");

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      debugPrint("DEBUG: Firebase Auth Success - UID: ${userCredential.user?.uid}");
      
      // Update lastLogin if user exists, otherwise redirection handles the role pick
      final userDoc = await _db.collection('users').doc(userCredential.user!.uid).get();
      debugPrint("DEBUG: Firestore Doc Exists: ${userDoc.exists}");
      if (userDoc.exists) {
        await _db.collection('users').doc(userCredential.user!.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
      
      return userCredential;
    } catch (e) {
      debugPrint("DEBUG: [ERROR] Google Sign-In failed: $e");
      String message = 'Google Sign-In failed: $e';
      
      // Handle known configuration errors (like SHA-1 mismatch)
      if (e.toString().contains('DEVELOPER_ERROR') || e.toString().contains('code 10')) {
        message = 'CONFIGURATION ERROR: Google Sign-In is misconfigured. Please ensure your SHA-1 fingerprint (from signingReport) is added to the Firebase Console.';
      } else if (e.toString().contains('network_error')) {
        message = 'NETWORK ERROR: Check your internet connection and try again.';
      }

      throw Exception(message);
    }
  }

  Future<void> completeUserProfile({
    required String name,
    required UserRole role,
    required String accessKey,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    // Key Verification Logic
    _verifyAccessKey(role, accessKey);

    final newUser = UserModel(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      role: role,
      assignedProjects: [],
      createdAt: DateTime.now(),
      lastLogin: DateTime.now(),
    );

    await _db.collection('users').doc(user.uid).set(newUser.toJson());
  }

  void _verifyAccessKey(UserRole role, String key) {
    const keys = {
      UserRole.admin: 'ADMIN_GUTS_2026',
      UserRole.manager: 'MGR_GUTS_2026',
      UserRole.engineer: 'ENG_GUTS_2026',
    };

    if (keys[role] != key) {
      throw Exception('Invalid Access Key for ${role.toString().split('.').last.toUpperCase()}. Registration denied.');
    }
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    required String accessKey,
  }) async {
    try {
      // RBC Check for all roles
      _verifyAccessKey(role, accessKey);

      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = UserModel(
        uid: cred.user!.uid,
        name: name,
        email: email,
        role: role,
        assignedProjects: [],
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );
      await _db.collection('users').doc(cred.user!.uid).set(user.toJson());
      return cred;
    } catch (e) {
      throw Exception('Registration failed: ${e.toString().split(']').last}');
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      // Also sign out from Google to force account selection next time
      await GoogleSignIn().signOut();
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
