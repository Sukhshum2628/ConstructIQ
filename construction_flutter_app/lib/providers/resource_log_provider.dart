import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/resource_log_service.dart';
import '../models/resource_log_model.dart';

import 'auth_provider.dart';
import '../constants/demo_data.dart';

final resourceLogServiceProvider = Provider<ResourceLogService>((ref) {
  return ResourceLogService();
});

final projectLogsProvider = StreamProvider.autoDispose.family<List<ResourceLogModel>, String>((ref, projectId) {
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    return Stream.value(kDemoResourceLogs);
  }

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
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    return Stream.value([
      {'date': DateTime.now().toIso8601String(), 'laborHours': 192.0, 'laborCount': 24},
      {'date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(), 'laborHours': 224.0, 'laborCount': 28},
    ]);
  }

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
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    return Stream.value(kDemoResourceLogs);
  }

  return FirebaseFirestore.instance
      .collectionGroup('resourceLogs')
      .orderBy('date', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => ResourceLogModel.fromJson(doc.data(), doc.id)).toList());
});
