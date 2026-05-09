import 'package:cloud_firestore/cloud_firestore.dart';

class MaterialDeviation {
  final double estimated;
  final double actual;
  final double deviationPct;
  final String unit;

  MaterialDeviation({
    required this.estimated,
    required this.actual,
    required this.deviationPct,
    required this.unit,
  });
}

class DeviationResult {
  final String projectId;
  final String deviationId;
  final Map<String, MaterialDeviation> perMaterial;
  final String overallSeverity;
  final bool flagged;
  final double mlOverrunProbability;
  final String aiInsightSummary;
  final int logCount;
  final DateTime computedAt;

  DeviationResult({
    required this.projectId,
    required this.deviationId,
    required this.perMaterial,
    required this.overallSeverity,
    required this.flagged,
    required this.mlOverrunProbability,
    required this.aiInsightSummary,
    required this.logCount,
    required this.computedAt,
  });

  factory DeviationResult.empty({required String summary}) {
    return DeviationResult(
      projectId: '',
      deviationId: '',
      perMaterial: {},
      overallSeverity: 'normal',
      flagged: false,
      mlOverrunProbability: 0.0,
      aiInsightSummary: summary,
      logCount: 0,
      computedAt: DateTime.now(),
    );
  }
}

// Legacy model for backward compatibility with existing code that might still use it
class DeviationModel {
  final String deviationId;
  final String projectId;
  final double deviationPct;
  final double zScore;
  final bool flagged;
  final String overallSeverity;
  final double mlOverrunProbability;
  final String aiInsightSummary;
  final Map<String, dynamic> breakdown;
  final DateTime createdAt;

  DeviationModel({
    required this.deviationId,
    required this.projectId,
    required this.deviationPct,
    required this.zScore,
    required this.flagged,
    required this.overallSeverity,
    required this.mlOverrunProbability,
    required this.aiInsightSummary,
    required this.breakdown,
    required this.createdAt,
  });

  factory DeviationModel.fromResult(DeviationResult result, String projectId) {
    return DeviationModel(
      deviationId: 'live_$projectId',
      projectId: projectId,
      deviationPct: result.perMaterial.values.isEmpty 
          ? 0.0 
          : result.perMaterial.values.fold(0.0, (sum, item) => sum + item.deviationPct) / result.perMaterial.length,
      zScore: 0.0,
      flagged: result.flagged,
      overallSeverity: result.overallSeverity,
      mlOverrunProbability: result.mlOverrunProbability,
      aiInsightSummary: result.aiInsightSummary,
      breakdown: {
        ...result.perMaterial.map((key, value) => MapEntry(key, {
          'estimated': value.estimated,
          'actual': value.actual,
          'deviationPct': value.deviationPct,
          'unit': value.unit,
        })),
        'anomalies': result.perMaterial.entries
            .where((e) => e.value.deviationPct.abs() > 10.0)
            .map((e) => {
                  'id': e.key,
                  'title': '${e.key[0].toUpperCase()}${e.key.substring(1)} Variance',
                  'description': 'Actual consumption is ${e.value.deviationPct.toStringAsFixed(1)}% ${e.value.deviationPct > 0 ? 'above' : 'below'} estimate.',
                  'severity': e.value.deviationPct.abs() > 20.0 ? 'critical' : 'warning',
                })
            .toList(),
      },
      createdAt: result.computedAt,
    );
  }

  factory DeviationModel.fromJson(Map<String, dynamic> json) {
    return DeviationModel(
      deviationId: json['deviationId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      deviationPct: (json['deviationPct'] as num? ?? 0.0).toDouble(),
      zScore: (json['zScore'] as num? ?? 0.0).toDouble(),
      flagged: json['flagged'] as bool? ?? false,
      overallSeverity: json['overallSeverity'] as String? ?? 'normal',
      mlOverrunProbability: (json['mlOverrunProbability'] as num? ?? 0.0).toDouble(),
      aiInsightSummary: json['aiInsightSummary'] as String? ?? '',
      breakdown: json['breakdown'] as Map<String, dynamic>? ?? {},
      createdAt: (json['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviationId': deviationId,
      'projectId': projectId,
      'deviationPct': deviationPct,
      'zScore': zScore,
      'flagged': flagged,
      'overallSeverity': overallSeverity,
      'mlOverrunProbability': mlOverrunProbability,
      'aiInsightSummary': aiInsightSummary,
      'breakdown': breakdown,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
