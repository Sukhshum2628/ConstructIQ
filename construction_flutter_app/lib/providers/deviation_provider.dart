import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/deviation_service.dart';
import '../models/deviation_model.dart';

final deviationServiceProvider = Provider((ref) => DeviationService());

// Provider to store the IDs of notifications that have been read by the user
final readNotificationsProvider = StateProvider<Set<String>>((ref) => {});

final projectDeviationProvider = FutureProvider.family<DeviationModel, String>((ref, projectId) async {
  final service = ref.watch(deviationServiceProvider);
  return service.analyzeProject(projectId);
});

// Stream the single most recent deviation for a project
final latestDeviationProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('deviations')
      .orderBy('generatedAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty ? null : snap.docs.first.data());
});

// Calculate global counts of project severities across all project sub-collections
final deviationSummaryProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final snapshot = await FirebaseFirestore.instance
      .collectionGroup('deviations')
      .orderBy('generatedAt', descending: true)
      .get();

  int warnings = 0, criticals = 0;
  final seen = <String>{};

  for (final doc in snapshot.docs) {
    // Get projectId from path: projects/{projectId}/deviations/{deviationId}
    final projectId = doc.reference.parent.parent!.id;
    if (seen.contains(projectId)) continue; // only latest per project
    seen.add(projectId);

    final severity = doc.data()['overallSeverity'] as String? ?? 'normal';
    if (severity == 'warning') warnings++;
    if (severity == 'critical') criticals++;
  }

  return {'warnings': warnings, 'criticals': criticals};
});

final overrunProbabilityProvider = FutureProvider.family<double, String>((ref, projectId) async {
  final service = ref.watch(deviationServiceProvider);
  return service.getOverrunPrediction(projectId);
});

final allDeviationsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collectionGroup('deviations')
      .orderBy('generatedAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => doc.data()).toList());
});
final projectDeviationsStreamProvider = StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('deviations')
      .orderBy('generatedAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((doc) => doc.data()).toList());
});
