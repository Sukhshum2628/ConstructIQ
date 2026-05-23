import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final userProfileProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateChangesProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(null);
  
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .where((doc) => !(doc.metadata.isFromCache && !doc.exists))
      .map((doc) => doc.exists ? UserModel.fromJson(doc.data()!) : null);
});

final currentUserProfileProvider = Provider<UserModel?>((ref) {
  return ref.watch(userProfileProvider).maybeWhen(
        data: (profile) => profile,
        orElse: () => null,
      );
});

final userNameProvider = FutureProvider.family<String, String>((ref, uid) async {
  if (uid.isEmpty) return 'Unassigned';
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  if (!doc.exists) return 'Unknown Team Member';
  return doc.data()?['name'] as String? ?? 'Unnamed Staff';
});
