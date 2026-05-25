import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

final allEngineersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'engineer')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .toList());
});

final allOwnersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'owner')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .toList());
});

final userByIdProvider = StreamProvider.autoDispose.family<UserModel?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? UserModel.fromJson(doc.data()!) : null);
});
