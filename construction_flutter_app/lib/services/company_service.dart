import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/invite_code_model.dart';
import '../models/user_model.dart';
import '../utils/exceptions.dart';

class CompanyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _formatCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No confusable chars like 0/O, 1/I
    final rand = Random.secure();
    final parts = List.generate(3, (_) =>
      List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join()
    );
    return parts.join('-'); // e.g. "XKQM-7B3N-P2WR"
  }

  /// Generates a new invite code for the current admin's company.
  Future<String> generateInviteCode({
    required UserRole role,
    int maxUses = 1,
    DateTime? expiresAt,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user found');

    // Authoritative check: read companyId and role from current user doc
    final userDoc = await _db.collection('users').doc(user.uid).get();
    if (!userDoc.exists) throw Exception('User record not found');
    
    final userData = userDoc.data()!;
    final companyId = userData['companyId'] as String?;
    final userRole = userData['role'] as String?;

    if (companyId == null || companyId.isEmpty) {
      throw const UnassignedCompanyException('User has no company assigned');
    }
    if (userRole != UserRole.admin.name) {
      throw Exception('Only administrators can generate company invite codes');
    }

    final code = _formatCode();
    final inviteCode = InviteCodeModel(
      code: code,
      companyId: companyId,
      role: role,
      createdBy: user.uid,
      maxUses: maxUses,
      usesSoFar: 0,
      isActive: true,
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );

    await _db.collection('inviteCodes').doc(code).set(inviteCode.toJson());
    return code;
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
