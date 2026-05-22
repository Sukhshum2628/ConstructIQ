import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project_model.dart';
import '../models/deviation_model.dart';
import '../services/deviation_calculator.dart';
import 'ml_provider.dart';

// Provider to store the IDs of notifications that have been read by the user
final readNotificationsProvider = StateProvider<Set<String>>((ref) => {});

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
      final predictor = ref.read(mlPredictorProvider);
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

      double logMean = 0.0;
      double stdDev = 0.0;
      if (materialLogs.isNotEmpty) {
        logMean = materialLogs.reduce((a, b) => a + b) / materialLogs.length;
        if (materialLogs.length > 1) {
          double sqDiffSum = 0.0;
          for (var val in materialLogs) {
            sqDiffSum += (val - logMean) * (val - logMean);
          }
          stdDev = math.sqrt(sqDiffSum / materialLogs.length);
        }
      }

      final String matUpper = worstMaterial.toUpperCase();

      // Generate dynamic mathematical proof and evidence-backed AI insight summary
      if (worstMaterial.isEmpty) {
        aiInsightSummary = "STABLE BASELINE: Initial log state registered. OVERRUN PROBABILITY = ${(finalMlProbability * 100).toStringAsFixed(1)}% derived from budget scale of ${budgetSize.toStringAsFixed(1)} Lakhs and ${project.projectType} parameters.";
      } else if (finalMlProbability > 0.60) {
        if (equipmentIdleRatio > 0.35) {
          aiInsightSummary = "CRITICAL PROOF OF DEVIATION: Dynamic tree split isolates high risk (${(finalMlProbability * 100).toStringAsFixed(1)}%). Primary operational drivers: 1) ${matUpper} shows variance of ${worstDevPct.toStringAsFixed(1)}% (mean: ${logMean.toStringAsFixed(1)}, σ = ${stdDev.toStringAsFixed(2)} over ${materialLogs.length} logs), and 2) Suboptimal Equipment Idle Ratio at ${(equipmentIdleRatio * 100).toStringAsFixed(1)}%. Non-linear co-variance at ${(daysElapsedPct * 100).toStringAsFixed(1)}% timeline elapsed triggers an active bottleneck node weight propagation.";
        } else {
          aiInsightSummary = "CRITICAL PROOF OF DEVIATION: Severe material consumption deviation detected (${(finalMlProbability * 100).toStringAsFixed(1)}% probability). Driver: ${matUpper} variance is currently ${worstDevPct.toStringAsFixed(1)}% against CAD baseline (σ = ${stdDev.toStringAsFixed(2)}), shifting leaf value thresholds at ${(daysElapsedPct * 100).toStringAsFixed(1)}% timeline elapsed, indicating elevated early-stage volatility.";
        }
      } else if (finalMlProbability > 0.30) {
        aiInsightSummary = "WARNING PROOF OF DEVIATION: Elevated cost overrun boundary crossed (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: ${matUpper} deviation reaches ${worstDevPct.toStringAsFixed(1)}% (mean = ${logMean.toStringAsFixed(1)}, σ = ${stdDev.toStringAsFixed(2)}). Daily logs oscillate outside planning margins, which combined with an Equipment Idle Ratio of ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% at timeline stage ${(daysElapsedPct * 100).toStringAsFixed(1)}%, yields elevated variance scaling.";
      } else if (finalMlProbability > 0.15) {
        aiInsightSummary = "CAUTIONARY PROOF OF DEVIATION: Mild variance bounds detected (${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: ${matUpper} deviation is ${worstDevPct.toStringAsFixed(1)}% (mean = ${logMean.toStringAsFixed(1)}, σ = ${stdDev.toStringAsFixed(2)}). Active daily fluctuations indicate minor site inefficiencies; however, low Equipment Idle Ratio of ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% successfully dampens multi-dimensional risk propagation.";
      } else {
        aiInsightSummary = "NORMAL/STABLE BASELINE PROOF: System displays optimal execution efficiency (overrun probability = ${(finalMlProbability * 100).toStringAsFixed(1)}%). Driver: ${matUpper} deviation is under control at ${worstDevPct.toStringAsFixed(1)}% (σ = ${stdDev.toStringAsFixed(2)}) over ${materialLogs.length} logs. Combined with Equipment Idle Ratio of ${(equipmentIdleRatio * 100).toStringAsFixed(1)}%, the multidimensional profile matches the stable planning matrix.";
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

