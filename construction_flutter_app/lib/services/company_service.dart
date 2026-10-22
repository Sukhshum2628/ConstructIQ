import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/invite_code_model.dart';
import '../models/user_model.dart';

class CompanyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Generates a new invite code for the current admin's company via Cloud Function.
  Future<String> generateInviteCode({
    required UserRole role,
    int maxUses = 1,
    DateTime? expiresAt,
    int? expiresInDays,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    int? computedDays = expiresInDays;
    if (computedDays == null && expiresAt != null) {
      computedDays = expiresAt.difference(DateTime.now()).inDays;
      if (computedDays <= 0) computedDays = 1;
    }

    final callable = FirebaseFunctions.instance.httpsCallable('generateInviteCode');
    
    final result = await callable.call({
      'role': role.name,
      'maxUses': maxUses,
      if (computedDays != null) 'expiresInDays': computedDays,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    return data['code'] as String;
  }

  /// Streams active invite codes for the current user's company.
  Stream<List<InviteCodeModel>> streamCompanyInviteCodes() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db.collection('users').doc(user.uid).snapshots().asyncExpand((userSnap) {
      if (!userSnap.exists) return Stream.value([]);
      final companyId = userSnap.data()?['companyId'] as String?;
      if (companyId == null || companyId.isEmpty) return Stream.value([]);

      return _db
          .collection('inviteCodes')
          .where('companyId', isEqualTo: companyId)
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => InviteCodeModel.fromJson(doc.data()))
              .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    });
  }

  /// Deactivates an invite code prematurely.
  Future<void> deactivateInviteCode(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final companyId = userDoc.data()?['companyId'] as String?;

    final codeDoc = await _db.collection('inviteCodes').doc(code).get();
    if (!codeDoc.exists) throw Exception('Invite code not found');

    if (codeDoc.data()?['companyId'] != companyId) {
      throw Exception('You cannot modify invite codes for another company');
    }

    await _db.collection('inviteCodes').doc(code).update({'isActive': false});
  }
}
