import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delay_notice_model.dart';

// All notices for a project (for manager view and engineer view)
final delayNoticesProvider = StreamProvider.autoDispose
    .family<List<DelayNotice>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('delayNotices')
      .orderBy('reportedDate', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(DelayNotice.fromFirestore).toList());
});

// Notices where this engineer needs to vote (pending_consensus, not yet voted)
final pendingVotesProvider = StreamProvider.autoDispose
    .family<List<DelayNotice>, ({String projectId, String uid})>((ref, args) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(args.projectId)
      .collection('delayNotices')
      .where('status', isEqualTo: 'pending_consensus')
      .snapshots()
      .map((snap) => snap.docs
          .map(DelayNotice.fromFirestore)
          .where((n) =>
              n.requiredVoters.contains(args.uid) &&
              !n.hasVoted(args.uid))
          .toList());
});

// Approved notices waiting for manager action
final approvedNoticesProvider = StreamProvider.autoDispose
    .family<List<DelayNotice>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('delayNotices')
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map((snap) => snap.docs.map(DelayNotice.fromFirestore).toList());
});
