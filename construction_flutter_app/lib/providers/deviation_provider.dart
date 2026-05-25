import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project_model.dart';
import '../models/deviation_model.dart';
import '../services/deviation_calculator.dart';
import 'ml_provider.dart';
import 'auth_provider.dart';

// Provider to store the IDs of notifications that have been read by the user
// Persisted read notifications per-user. Stored in users/{uid}.readNotifications (array of ids).
class ReadNotificationsNotifier extends StateNotifier<Set<String>> {
  final Ref ref;
  ReadNotificationsNotifier(this.ref) : super({}) {
    _init();
    // When auth changes, reload read ids for new user
    ref.listen(authStateChangesProvider, (previous, next) {
      _init();
    });
  }

  Future<void> _init() async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    if (uid == null) {
      state = {};
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final list = (doc.data()?['readNotifications'] as List?)?.cast<String>() ?? [];
        state = Set<String>.from(list);
      } else {
        state = {};
      }
    } catch (e) {
      // Keep in-memory state if Firestore read fails
    }
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty) return;
    final uid = ref.read(authStateChangesProvider).value?.uid;
    state = {...state, id};
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({'readNotifications': state.toList()}, SetOptions(merge: true));
  }

  Future<void> markAllRead(Iterable<String> ids) async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    state = {...state, ...ids};
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({'readNotifications': state.toList()}, SetOptions(merge: true));
  }

  Future<void> clear() async {
    final uid = ref.read(authStateChangesProvider).value?.uid;
    state = {};
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({'readNotifications': []}, SetOptions(merge: true));
  }
}

final readNotificationsProvider = StateNotifierProvider<ReadNotificationsNotifier, Set<String>>((ref) => ReadNotificationsNotifier(ref));

// Stream provider for project document changes. Used so deviation calculations
// re-run when project fields (like expectedEndDate) change.
final projectDocStreamProvider = StreamProvider.autoDispose.family<DocumentSnapshot<Map<String, dynamic>>?, String>((ref, projectId) {
  return FirebaseFirestore.instance.collection('projects').doc(projectId).snapshots();
});

// The new core deviation provider using live computation
final deviationProvider = FutureProvider.autoDispose.family<DeviationResult, String>((ref, projectId) async {
  // Watch auth state to handle reactive cleanup & invalidation on logout
  final authState = ref.watch(authStateChangesProvider);
  if (authState.value == null) {
    return DeviationResult(
      projectId: projectId,
      deviationId: 'logged_out_$projectId',
      perMaterial: {},
      overallSeverity: 'normal',
      flagged: false,
      mlOverrunProbability: 0.0,
      aiInsightSummary: "Not authenticated.",
      logCount: 0,
      computedAt: DateTime.now(),
    );
  }

  // Keep alive to prevent lag on scroll and unnecessary ONNX prediction cycles
  ref.keepAlive();

  // Watch mlPredictorProvider to align ML Predictor Service lifecycle
  ref.watch(mlPredictorProvider);

  // Make provider reactive to project changes (expectedEndDate updates)
  ref.watch(projectDocStreamProvider(projectId));

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

  final Map estimatedMaterials = estimateSnap.docs.first.data()['estimatedMaterials'] as Map? ?? {};

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

  // 3. Compute live arithmetic deviation first
  final baseResult = DeviationCalculator.calculateDeviation(
    projectId: projectId,
    deviationId: 'live_$projectId',
    estimatedMaterials: estimatedMaterials,
    resourceLogs: resourceLogs,
  );

  // 4. Ingest multi-dimensional project features to run the on-device XGBoost Classifier (ONNX)
  double finalMlProbability = baseResult.mlOverrunProbability;
  String overallSeverity = baseResult.overallSeverity;
  String aiInsightSummary = baseResult.aiInsightSummary;
  bool flagged = baseResult.flagged;

  try {
    final projectSnap = await FirebaseFirestore.instance
        .collection('projects')
        .doc(projectId)
        .get();

    if (projectSnap.exists) {
      final projectData = projectSnap.data()!;
      final project = ProjectModel.fromJson(projectData);

      // Feature 0 (f0): material_deviation_avg (average % deviation / 100)
      double sumPct = 0.0;
      int matCount = 0;
      baseResult.perMaterial.forEach((key, matDev) {
        sumPct += matDev.deviationPct;
        matCount++;
      });
      double materialDeviationAvg = matCount > 0 ? (sumPct / matCount) / 100.0 : 0.0;

      // Feature 1 (f1): equipment_idle_ratio (idle hours / total hours across all machines)
      double totalUsed = 0.0;
      double totalIdle = 0.0;
      for (var log in resourceLogs) {
        final eqList = log['equipmentList'] as List? ?? log['equipment'] as List? ?? [];
        for (var eq in eqList) {
          if (eq is Map) {
            totalUsed += (eq['usedHours'] as num? ?? eq['used'] as num? ?? 0.0).toDouble();
            totalIdle += (eq['idleHours'] as num? ?? eq['idle'] as num? ?? 0.0).toDouble();
          }
        }
      }
      double equipmentIdleRatio = (totalUsed + totalIdle) > 0 ? totalIdle / (totalUsed + totalIdle) : 0.0;

      // Feature 2 (f2): days_elapsed_pct (days elapsed / total duration, normalized 0.0-1.0)
      double daysElapsedPct = calculateDaysElapsedPct(project.startDate, project.expectedEndDate);

      // Feature 3 (f3): budget_size (planned budget in lakhs, e.g. 45.0)
      double budgetSize = project.plannedBudget;

      // Feature 4 (f4): project_type_encoded (0=residential, 1=commercial, 2=infrastructure)
      int projectTypeEncoded = encodeProjectType(project.projectType);

      // Invoke the on-device XGBoost Predictor Service
      final predictor = ref.watch(mlPredictorProvider);
      final mlResult = await predictor.predictOverrun(
        materialDeviationAvg: materialDeviationAvg,
        equipmentIdleRatio: equipmentIdleRatio,
        daysElapsedPct: daysElapsedPct,
        budgetSize: budgetSize,
        projectTypeEncoded: projectTypeEncoded,
      );

      finalMlProbability = (mlResult['probability'] as num? ?? 0.0).toDouble();

      // Align severity with the patterns learned by the XGBoost model
      if (finalMlProbability > 0.60) {
        overallSeverity = 'critical';
        flagged = true;
      } else if (finalMlProbability > 0.30) {
        if (overallSeverity != 'critical') {
          overallSeverity = 'warning';
        }
        flagged = true;
      } else if (finalMlProbability > 0.15) {
        if (overallSeverity != 'critical' && overallSeverity != 'warning') {
          overallSeverity = 'caution';
        }
      } else {
        overallSeverity = 'normal';
      }

      // Find the material with the highest absolute deviation percentage
      String worstMaterial = '';
      double worstDevPct = 0.0;
      baseResult.perMaterial.forEach((key, matDev) {
        if (matDev.deviationPct.abs() > worstDevPct.abs()) {
          worstDevPct = matDev.deviationPct;
          worstMaterial = key;
        }
      });

      // Calculate standard deviation and logs count for worst material
      List<double> materialLogs = [];
      if (worstMaterial.isNotEmpty) {
        for (var log in resourceLogs) {
          final usage = log['materialUsage'] as Map? ?? log['materials'] as Map? ?? {};
          final val = (usage[worstMaterial] ?? 
                       usage['${worstMaterial}_bags'] ?? 
                       usage['${worstMaterial}_kg'] ?? 
                       usage['${worstMaterial}_m3'] ?? 
                       0.0).toDouble();
          if (val > 0) {
            materialLogs.add(val);
          }
        }
      }


      final String matUpper = worstMaterial.toUpperCase();

      // Generate dynamic site-friendly AI insight summary
      if (worstMaterial.isEmpty) {
        aiInsightSummary = "STABLE BASELINE: The project is running normally in its initial stage. Overrun risk is low at ${(finalMlProbability * 100).toStringAsFixed(1)}%, based on a budget scale of ${budgetSize.toStringAsFixed(1)} Lakhs for ${project.projectType} works.";
      } else if (finalMlProbability > 0.60) {
        if (equipmentIdleRatio > 0.35) {
          aiInsightSummary = "CRITICAL DEVIATION DETECTED: High budget risk (${(finalMlProbability * 100).toStringAsFixed(1)}%) identified. Primary operational causes: 1) $matUpper consumption is ${worstDevPct.toStringAsFixed(1)}% higher than planned over the last ${materialLogs.length} logs, and 2) Machinery is sitting idle ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% of the time. At this stage of the project (${(daysElapsedPct * 100).toStringAsFixed(1)}% timeline complete), these bottlenecks could significantly delay overall progress and increase costs.";
        } else {
          aiInsightSummary = "CRITICAL DEVIATION DETECTED: High material overconsumption risk (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: $matUpper usage has surged by ${worstDevPct.toStringAsFixed(1)}% compared to the blueprint estimate. Since the project is only ${(daysElapsedPct * 100).toStringAsFixed(1)}% through its timeline, this early-stage overconsumption requires immediate correction to prevent major budget overruns.";
        }
      } else if (finalMlProbability > 0.30) {
        aiInsightSummary = "WARNING: Cost overrun risk is elevated (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: $matUpper usage has deviated by ${worstDevPct.toStringAsFixed(1)}% from planned quantities. Daily consumption shows unstable fluctuations, which combined with a machinery idle ratio of ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% at ${(daysElapsedPct * 100).toStringAsFixed(1)}% timeline completion, indicates potential site inefficiencies.";
      } else if (finalMlProbability > 0.15) {
        aiInsightSummary = "CAUTION: Minor consumption variance detected (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: $matUpper usage is ${worstDevPct.toStringAsFixed(1)}% off-plan. While daily logs fluctuate, active machinery utilization is high (only ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% idle time), which helps keep overall project risk low.";
      } else {
        aiInsightSummary = "EXCELLENT STATUS: The project is highly stable with low overrun risk (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: $matUpper consumption is well under control with only a ${worstDevPct.toStringAsFixed(1)}% minor variance. Combined with optimal equipment utilization (idle ratio at ${(equipmentIdleRatio * 100).toStringAsFixed(1)}%), the site is tracking closely to the budget and schedule.";
      }
    }
  } catch (e) {
    debugPrint('[ML Provider] Error running live ONNX prediction: $e');
  }

  return DeviationResult(
    projectId: baseResult.projectId,
    deviationId: baseResult.deviationId,
    perMaterial: baseResult.perMaterial,
    overallSeverity: overallSeverity,
    flagged: flagged,
    mlOverrunProbability: finalMlProbability,
    aiInsightSummary: aiInsightSummary,
    logCount: baseResult.logCount,
    computedAt: baseResult.computedAt,
  );
});

// Alias for backward compatibility with existing screens
final latestDeviationProvider = deviationProvider;

// Stub for collection-wide deviations (used in Manager Dashboard)
// In a real app, this would iterate over all projects and call deviationProvider for each,
// or use a cloud function to aggregate. For demo/seeding stability, we return an empty list or mock.
final allDeviationsProvider = FutureProvider.autoDispose<List<DeviationResult>>((ref) async {
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
final deviationSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
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
final projectDeviationsStreamProvider = FutureProvider.autoDispose.family<List<DeviationResult>, String>((ref, projectId) async {
  final res = await ref.watch(deviationProvider(projectId).future);
  return [res];
});

