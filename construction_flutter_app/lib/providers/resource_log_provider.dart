import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/resource_log_service.dart';
import '../models/resource_log_model.dart';

final resourceLogServiceProvider = Provider<ResourceLogService>((ref) {
  return ResourceLogService();
});

final projectLogsProvider = StreamProvider.autoDispose.family<List<ResourceLogModel>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('resourceLogs')
      .orderBy('date', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => ResourceLogModel.fromJson(doc.data(), doc.id)).toList());
});

// For the 7-day chart in dashboard (raw data is easier for charts)
final resourceLogsProvider = StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('resourceLogs')
      .orderBy('date', descending: true)
      .limit(7)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => doc.data()).toList());
});

final allLogsProvider = StreamProvider.autoDispose<List<ResourceLogModel>>((ref) {
  return FirebaseFirestore.instance
      .collectionGroup('resourceLogs')
      .orderBy('date', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => ResourceLogModel.fromJson(doc.data(), doc.id)).toList());
});
