import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/delay_notice_model.dart';

class DelayNoticeService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  // STEP A: Engineer creates a notice
  Future<void> createNotice({
    required String projectId,
    required String type,
    required String title,
    required String description,
    required List<String> affectedMaterials,
    required DateTime expectedDeliveryDate,
    required String creatorName,
    required List<String> otherEngineerUids, // all engineers on project except creator
  }) async {
    final ref = _db
        .collection('projects')
        .doc(projectId)
        .collection('delayNotices')
        .doc();

    // Creator auto-votes agree
    final creatorVote = {
      _uid: {
        'vote': 'agree',
        'comment': 'Filed this notice',
        'votedAt': Timestamp.now(),
        'engineerName': creatorName,
      }
    };

    // If no other engineers, immediately approve
    final initialStatus = otherEngineerUids.isEmpty
        ? 'approved'
        : 'pending_consensus';

    await ref.set({
      'id': ref.id,
      'projectId': projectId,
      'type': type,
      'title': title,
      'description': description,
      'affectedMaterials': affectedMaterials,
      'expectedDeliveryDate': Timestamp.fromDate(expectedDeliveryDate),
      'reportedDate': Timestamp.now(),
      'createdBy': _uid,
      'createdByName': creatorName,
      'status': initialStatus,
      'votes': creatorVote,
      'requiredVoters': otherEngineerUids,
      'consensusAt': otherEngineerUids.isEmpty ? Timestamp.now() : null,
      'managerResponse': null,
    });
  }

  // STEP B: Engineer votes on a peer's notice
  Future<void> castVote({
    required String projectId,
    required String noticeId,
    required String engineerName,
    required VoteChoice vote,
    required String comment,
    required DelayNotice notice,
  }) async {
    final voteEntry = {
      'vote': vote == VoteChoice.agree ? 'agree' : 'disagree',
      'comment': comment,
      'votedAt': Timestamp.now(),
      'engineerName': engineerName,
    };

    // Add vote
    final ref = _db
        .collection('projects')
        .doc(projectId)
        .collection('delayNotices')
        .doc(noticeId);

    await ref.update({'votes.$_uid': voteEntry});

    // Re-read to check consensus
    final updated = await ref.get();
    final updatedNotice = DelayNotice.fromFirestore(updated);

    // Check if all required voters have voted OR majority is reached
    final totalVoters = updatedNotice.totalVoters;
    final agreeCount = updatedNotice.agreeCount;
    final disagreeCount = updatedNotice.disagreeCount;

    final majorityThreshold = (totalVoters / 2).ceil();

    if (agreeCount >= majorityThreshold) {
      // Majority agrees — approve
      await ref.update({
        'status': 'approved',
        'consensusAt': Timestamp.now(),
      });
    } else if (disagreeCount >= majorityThreshold) {
      // Majority disagrees — reject by team
      await ref.update({
        'status': 'rejected_by_team',
        'consensusAt': Timestamp.now(),
      });
    }
    // Otherwise: more votes needed, no status change
  }

  // STEP C: Manager responds to an approved notice
  Future<void> managerRespond({
    required String projectId,
    required String noticeId,
    required String decision,  // 'extend' | 'no_extension' | 'reject'
    required int daysExtended,
    required String managerNote,
    required String managerId,
  }) async {
    final batch = _db.batch();

    // Update the notice
    final noticeRef = _db
        .collection('projects')
        .doc(projectId)
        .collection('delayNotices')
        .doc(noticeId);

    String newStatus = switch (decision) {
      'extend'       => 'acknowledged_extended',
      'no_extension' => 'acknowledged_no_extension',
      _              => 'rejected_by_manager',
    };

    batch.update(noticeRef, {
      'status': newStatus,
      'managerResponse': {
        'respondedBy': managerId,
        'respondedAt': Timestamp.now(),
        'decision': decision,
        'daysExtended': daysExtended,
        'managerNote': managerNote,
      },
      'daysAdded': daysExtended,
    });

    // If extending: update project endDate and create delay record
    if (decision == 'extend' && daysExtended > 0) {
      final projectRef = _db.collection('projects').doc(projectId);
      final projectSnap = await projectRef.get();
      final data = projectSnap.data() as Map<String, dynamic>;

      // Get current endDate
      // Note: We should check if 'endDate' exists, or 'expectedEndDate'
      // README says 'expectedEndDate'
      final endField = data.containsKey('expectedEndDate') ? 'expectedEndDate' : 'endDate';
      final currentEndTs = data[endField] as Timestamp;
      final currentEnd = currentEndTs.toDate();
      final newEnd = currentEnd.add(Duration(days: daysExtended));

      // Preserve originalEndDate if not already set
      if (data['originalEndDate'] == null) {
        batch.update(projectRef, {
          'originalEndDate': currentEndTs,
        });
      }

      batch.update(projectRef, {
        endField: Timestamp.fromDate(newEnd),
        if (data.containsKey('durationDays')) 'durationDays': (data['durationDays'] as int) + daysExtended,
      });

      // Create delay record
      final delayRef = _db
          .collection('projects')
          .doc(projectId)
          .collection('delays')
          .doc();

      batch.set(delayRef, {
        'type': 'material_delivery',
        'noticeId': noticeId,
        'daysAdded': daysExtended,
        'addedAt': Timestamp.now(),
        'addedBy': managerId,
        'managerNote': managerNote,
        'verified': true,
      });
    }

    await batch.commit();
  }
}
