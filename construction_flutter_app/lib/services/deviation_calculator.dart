import 'dart:math';
import '../models/deviation_model.dart';

class DeviationCalculator {
  static DeviationResult calculateDeviation({
    required String projectId,
    required String deviationId,
    required Map estimatedMaterials,
    required List<Map<String, dynamic>> resourceLogs,
  }) {
    if (estimatedMaterials.isEmpty) {
      return DeviationResult.empty(
        summary: 'No estimate linked to this project.'
      );
    }

    double _readQty(Map mats, String key) {
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
      final Map usage = log['materialUsage'] as Map? ?? log['materials'] as Map? ?? {};
      // Support both user-requested keys and potential seed fallbacks
      actualCement += (usage['cement'] as num? ?? usage['cement_bags'] as num? ?? 0.0).toDouble();
      actualBricks += (usage['bricks'] as num? ?? usage['brick'] as num? ?? 0.0).toDouble();
      actualSteel += (usage['rebar'] as num? ?? usage['steel'] as num? ?? usage['steel_kg'] as num? ?? 0.0).toDouble();
      actualSand += (usage['sand'] as num? ?? usage['sand_m3'] as num? ?? 0.0).toDouble();
      actualAggregate += (usage['aggregate'] as num? ?? usage['aggregate_m3'] as num? ?? 0.0).toDouble();
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
    double maxOverrunDeviation = 0;
    double maxAbsDeviation = 0;
    
    String highestOverrunMaterial = '';
    double highestOverrunValue = -1.0;

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
        maxOverrunDeviation = max(maxOverrunDeviation, deviationPct);
        if (deviationPct > highestOverrunValue) {
          highestOverrunValue = deviationPct;
          highestOverrunMaterial = key;
        }
      }
    });

    // 4. Calculate overall severity (Prioritize Overruns for CRITICAL/WARNING)
    String severity = 'normal';
    bool flagged = false;
    
    if (maxOverrunDeviation > 15.0) {
      severity = 'critical';
      flagged = true;
    } else if (maxOverrunDeviation > 7.0) {
      severity = 'warning';
      flagged = true;
    } else if (maxAbsDeviation > 25.0) {
      // Large underrun or slight overrun
      severity = 'caution';
      flagged = false;
    }

    // 5. Calculate mlOverrunProbability
    // Focus probability on how close we are to overrunning or by how much we have overshot
    final mlOverrunProbability = (maxOverrunDeviation / 30.0).clamp(0.0, 1.0);

    // 6. Build aiInsightSummary
    String aiInsightSummary = '';
    if (highestOverrunValue > 0) {
      aiInsightSummary = "${highestOverrunMaterial[0].toUpperCase()}${highestOverrunMaterial.substring(1)} consumption is ${highestOverrunValue.toStringAsFixed(1)}% above estimate. Resource tracking shows possible wastage.";
    } else if (maxAbsDeviation > 10.0) {
      aiInsightSummary = "Project consumption is significantly below estimate. Verify if all daily logs have been submitted.";
    } else {
      aiInsightSummary = "All materials tracking optimally within budget estimates. Total logs: $logCount.";
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
