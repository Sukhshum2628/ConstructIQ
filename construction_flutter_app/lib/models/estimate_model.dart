import 'package:cloud_firestore/cloud_firestore.dart';

enum EstimationConfidence { high, medium, low }

class EstimateModel {
  final String estimateId;
  final DateTime generatedAt;
  final String cadFileName;
  final Map<String, double> geometryData;
  final Map<String, Map<String, dynamic>> estimatedMaterials;
  final EstimationConfidence confidence;
  final Map<String, dynamic>? labour;
  final int? totalLabourDays;
  final String? disclaimer;
  final List<String>? assumptions;

  EstimateModel({
    required this.estimateId,
    required this.generatedAt,
    required this.cadFileName,
    required this.geometryData,
    required this.estimatedMaterials,
    required this.confidence,
    this.labour,
    this.totalLabourDays,
    this.disclaimer,
    this.assumptions,
  });

  factory EstimateModel.fromJson(Map<String, dynamic> json) {
    return EstimateModel(
      estimateId: json['estimateId'] as String? ?? 'est_unknown',
      generatedAt: json['generatedAt'] != null 
          ? (json['generatedAt'] as Timestamp).toDate() 
          : DateTime.now(),
      cadFileName: json['cadFileName'] as String? ?? 'unknown_file.dxf',
      geometryData: json['geometryData'] != null 
          ? (json['geometryData'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            )
          : {},
      estimatedMaterials: json['estimatedMaterials'] != null
          ? Map<String, Map<String, dynamic>>.from(json['estimatedMaterials'])
          : {},
      confidence: json['confidence'] != null
          ? EstimationConfidence.values.firstWhere(
              (e) => e.name == json['confidence'],
              orElse: () => EstimationConfidence.medium,
            )
          : EstimationConfidence.medium,
      labour: json['labour'] as Map<String, dynamic>?,
      totalLabourDays: json['totalLabourDays'] as int?,
      disclaimer: json['disclaimer'] as String?,
      assumptions: json['assumptions'] != null 
          ? List<String>.from(json['assumptions']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'estimateId': estimateId,
      'generatedAt': Timestamp.fromDate(generatedAt),
      'cadFileName': cadFileName,
      'geometryData': geometryData,
      'estimatedMaterials': estimatedMaterials,
      'confidence': confidence.name,
      'labour': labour,
      'totalLabourDays': totalLabourDays,
      'disclaimer': disclaimer,
      'assumptions': assumptions,
    };
  }
}
