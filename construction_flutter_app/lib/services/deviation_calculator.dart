import 'dart:math';
import '../models/deviation_model.dart';

class DeviationCalculator {
  static DeviationResult calculateDeviation({
    required String projectId,
    required String deviationId,
    required Map<String, dynamic> estimatedMaterials,
    required List<Map<String, dynamic>> resourceLogs,
  }) {
    if (estimatedMaterials.isEmpty) {
      return DeviationResult.empty(
        summary: 'No estimate linked to this project.'
      );
    }

    double _readQty(Map<String, dynamic> mats, String key) {
      final val = mats[key];
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();           // flat schema
      if (val is Map) {
        final q = val['quantity'];
        return (q as num?)?.toDouble() ?? 0.0;        // nested schema
      }
      return 0.0;
    }

    final int logCount = resourceLogs.length;
    final DateTime now = DateTime.now();

    // 1. Build a map of estimated quantities per material
    final Map<String, double> estimates = {
      'cement': _readQty(estimatedMaterials, 'cement'),
      'bricks': _readQty(estimatedMaterials, 'bricks'),
      'steel': _readQty(estimatedMaterials, 'steel'),
      'sand': _readQty(estimatedMaterials, 'sand'),
      'aggregate': _readQty(estimatedMaterials, 'aggregate'),
    };

    final Map<String, String> units = {
      'cement': estimatedMaterials['cement'] is Map ? (estimatedMaterials['cement']?['unit']?.toString() ?? 'bags') : 'bags',
      'bricks': estimatedMaterials['bricks'] is Map ? (estimatedMaterials['bricks']?['unit']?.toString() ?? 'nos') : 'nos',
      'steel': estimatedMaterials['steel'] is Map ? (estimatedMaterials['steel']?['unit']?.toString() ?? 'kg') : 'kg',
      'sand': estimatedMaterials['sand'] is Map ? (estimatedMaterials['sand']?['unit']?.toString() ?? 'm3') : 'm3',
      'aggregate': estimatedMaterials['aggregate'] is Map ? (estimatedMaterials['aggregate']?['unit']?.toString() ?? 'm3') : 'm3',
    };

    // 2. Sum actual consumed quantities across ALL resourceLogs
    double actualCement = 0;
    double actualBricks = 0;
    double actualSteel = 0;
    double actualSand = 0;
    double actualAggregate = 0;

    for (var log in resourceLogs) {
      final usage = log['materialUsage'] as Map<String, dynamic>? ?? {};
      // Support both user-requested keys and potential seed fallbacks
      actualCement += (usage['cement_bags'] as num? ?? usage['cement'] as num? ?? 0.0).toDouble();
      actualBricks += (usage['bricks'] as num? ?? 0.0).toDouble();
      actualSteel += (usage['steel_kg'] as num? ?? usage['steel'] as num? ?? 0.0).toDouble();
      actualSand += (usage['sand_m3'] as num? ?? usage['sand'] as num? ?? 0.0).toDouble();
      actualAggregate += (usage['aggregate_m3'] as num? ?? usage['aggregate'] as num? ?? 0.0).toDouble();
    }

    final Map<String, double> actuals = {
      'cement': actualCement,
      'bricks': actualBricks,
      'steel': actualSteel,
      'sand': actualSand,
      'aggregate': actualAggregate,
    };

    // 3. Calculate deviation per material
    final Map<String, MaterialDeviation> perMaterial = {};
    double maxAbsDeviation = 0;
    double sumPositiveDeviation = 0;
    int positiveDeviationCount = 0;
    String highestPositiveMaterial = '';
    double highestPositiveValue = -1.0;

    estimates.forEach((key, estimated) {
      final actual = actuals[key] ?? 0.0;
      double deviationPct = 0;
      if (estimated > 0) {
        deviationPct = ((actual - estimated) / estimated) * 100;
      }

      perMaterial[key] = MaterialDeviation(
        estimated: estimated,
        actual: actual,
        deviationPct: deviationPct,
        unit: units[key] ?? '',
      );

      maxAbsDeviation = max(maxAbsDeviation, deviationPct.abs());
      
      if (deviationPct > 0) {
        sumPositiveDeviation += deviationPct;
        positiveDeviationCount++;
        if (deviationPct > highestPositiveValue) {
          highestPositiveValue = deviationPct;
          highestPositiveMaterial = key;
        }
      }
    });

    // 4. Calculate overall severity
    String severity = 'normal';
    bool flagged = false;
    if (maxAbsDeviation > 20.0) {
      severity = 'critical';
      flagged = true;
    } else if (maxAbsDeviation > 10.0) {
      severity = 'warning';
      flagged = true;
    } else if (maxAbsDeviation > 5.0) {
      severity = 'caution';
      flagged = false;
    }

    // 5. Calculate mlOverrunProbability heuristic using absolute deviations
    final allPcts = perMaterial.values
        .map((m) => m.deviationPct.abs())
        .toList();
    final avgAbsDev = allPcts.isEmpty ? 0.0 
        : allPcts.reduce((a, b) => a + b) / allPcts.length;
    final mlOverrunProbability = (avgAbsDev / 40.0).clamp(0.0, 1.0);

    // 6. Build aiInsightSummary
    String aiInsightSummary = '';
    if (highestPositiveValue > 0) {
      aiInsightSummary = "${highestPositiveMaterial[0].toUpperCase()}${highestPositiveMaterial.substring(1)} consumption is ${highestPositiveValue.toStringAsFixed(1)}% above estimate. Total logs analyzed: $logCount.";
    } else {
      aiInsightSummary = "All materials tracking within estimate. Total logs: $logCount.";
    }

    return DeviationResult(
      projectId: projectId,
      deviationId: deviationId,
      perMaterial: perMaterial,
      overallSeverity: severity,
      flagged: flagged,
      mlOverrunProbability: mlOverrunProbability,
      aiInsightSummary: aiInsightSummary,
      logCount: logCount,
      computedAt: now,
    );
  }
}
