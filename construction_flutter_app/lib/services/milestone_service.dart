import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/milestone_model.dart';

class MilestoneService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String projectId) =>
      _db.collection('projects').doc(projectId).collection('milestones');

  Future<void> save(MilestoneModel m) =>
      _col(m.projectId).doc(m.id).set(m.toJson(), SetOptions(merge: true));

  Future<void> delete(String projectId, String id) =>
      _col(projectId).doc(id).delete();

  /// Updates progress and stamps/clears the completion date at 100%.
  Future<void> setProgress(String projectId, String id, double progress) =>
      _col(projectId).doc(id).set({
        'progress': progress,
        'completedAt': progress >= 100 ? Timestamp.now() : null,
      }, SetOptions(merge: true));
}

final milestoneServiceProvider = Provider((ref) => MilestoneService());
