import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/deviation_model.dart';
import '../services/deviation_calculator.dart';

// Provider to store the IDs of notifications that have been read by the user
final readNotificationsProvider = StateProvider<Set<String>>((ref) => {});

// The new core deviation provider using live computation
// The new core deviation provider using live computation
final deviationProvider = FutureProvider.family<DeviationResult, String>((ref, projectId) async {
  // 1. Fetch latest estimate
  final estimateSnap = await FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('estimates')
      .orderBy('generatedAt', descending: true)
      .limit(1)
      .get();

  if (estimateSnap.docs.isEmpty) {
    return DeviationResult(
      projectId: projectId,
      deviationId: 'no_estimate_$projectId',
      perMaterial: {},
      overallSeverity: 'normal',
      flagged: false,
      mlOverrunProbability: 0.0,
      aiInsightSummary: "No CAD estimate found for this project.",
      logCount: 0,
      computedAt: DateTime.now(),
    );
  }

  final estimatedMaterials = estimateSnap.docs.first.data()['estimatedMaterials'] as Map<String, dynamic>? ?? {};

  // 2. Fetch ALL resource logs
  final logsSnap = await FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('resourceLogs')
      .orderBy('logDate', descending: true)
      .get();

  if (logsSnap.docs.isEmpty) {
    return DeviationResult(
      projectId: projectId,
      deviationId: 'no_logs_$projectId',
      perMaterial: {},
      overallSeverity: 'normal',
      flagged: false,
      mlOverrunProbability: 0.0,
      aiInsightSummary: "No log entries yet. Add daily logs to see deviation analysis.",
      logCount: 0,
      computedAt: DateTime.now(),
    );
  }

  final resourceLogs = logsSnap.docs.map((doc) => doc.data()).toList();

  // 3. Compute live deviation
  return DeviationCalculator.calculateDeviation(
    projectId: projectId,
    deviationId: 'live_$projectId',
    estimatedMaterials: estimatedMaterials,
    resourceLogs: resourceLogs,
  );
});

// Alias for backward compatibility with existing screens
final latestDeviationProvider = deviationProvider;

// Stub for collection-wide deviations (used in Manager Dashboard)
// In a real app, this would iterate over all projects and call deviationProvider for each,
// or use a cloud function to aggregate. For demo/seeding stability, we return an empty list or mock.
final allDeviationsProvider = FutureProvider<List<DeviationResult>>((ref) async {
  final projectsSnap = await FirebaseFirestore.instance.collection('projects').get();
  final List<DeviationResult> results = [];
  
  for (var doc in projectsSnap.docs) {
    try {
      final res = await ref.read(deviationProvider(doc.id).future);
      results.add(res);
    } catch (e) {
      // Skip projects with errors
    }
  }
  return results;
});

// Stub for summary (used in Manager Dashboard)
final deviationSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final devs = await ref.watch(allDeviationsProvider.future);
  int critical = devs.where((d) => d.overallSeverity == 'critical').length;
  int warning = devs.where((d) => d.overallSeverity == 'warning' || d.overallSeverity == 'caution').length;
  
  return {
    'criticals': critical,
    'warnings': warning,
    'totalTracked': devs.length,
  };
});

// Alias for engineer home stream - wrapped in a list for legacy compatibility
final projectDeviationsStreamProvider = FutureProvider.family<List<DeviationResult>, String>((ref, projectId) async {
  final res = await ref.watch(deviationProvider(projectId).future);
  return [res];
});

