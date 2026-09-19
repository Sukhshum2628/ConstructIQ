import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../constants/demo_data.dart';

final isDemoModeProvider = StateProvider<bool>((ref) => false);

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final userProfileProvider = StreamProvider<UserModel?>((ref) {
  final isDemo = ref.watch(isDemoModeProvider);
  final currentUser = FirebaseAuth.instance.currentUser;

  if (isDemo || (currentUser != null && currentUser.isAnonymous)) {
    final demoUser = UserModel(
      uid: currentUser?.uid ?? 'demo_user',
      name: kDemoUserName,
      email: kDemoUserEmail,
      role: UserRole.admin,
      companyId: kDemoCompanyId,
      phone: '+91 98765 43210',
      designation: 'Portfolio Director (Demo)',
      assignedProjects: ['demo_project_1', 'demo_project_2', 'demo_project_3'],
      createdAt: DateTime(2026, 1, 1),
      lastLogin: DateTime.now(),
    );
    return Stream.value(demoUser);
  }

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
  if (ref.watch(isDemoModeProvider) || FirebaseAuth.instance.currentUser?.isAnonymous == true) {
    return kDemoUserName;
  }
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  if (!doc.exists) return 'Unknown Team Member';
  return doc.data()?['name'] as String? ?? 'Unnamed Staff';
});
