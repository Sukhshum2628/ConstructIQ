import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/milestone_model.dart';

final projectMilestonesProvider = StreamProvider.autoDispose
    .family<List<MilestoneModel>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('milestones')
      .orderBy('order')
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => MilestoneModel.fromJson(d.data(), d.id))
          .toList());
});
