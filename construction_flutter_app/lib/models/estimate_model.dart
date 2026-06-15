import 'package:cloud_firestore/cloud_firestore.dart';

enum EstimationConfidence { high, medium, low }

class EstimateModel {
  final String estimateId;
  final DateTime generatedAt;
  final String cadFileName;
  final Map<String, double> geometryData;
  final Map<String, Map<String, dynamic>> estimatedMaterials;
  final Map<String, dynamic>? interiorMaterials; // tiles/paint/fixtures/electrical
  final String? estimationType; // 'structural' | 'interior' | 'both'
  // Selected material specs (Phase 1): {'brickType': ..., 'floorTileSize': ...}.
  final Map<String, dynamic>? materialSpecs;
  final EstimationConfidence confidence;
  final Map<String, dynamic>? labour;
  final int? totalLabourDays;
  final String? disclaimer;
  final List<String>? assumptions;
  
  // Manual override fields
  final double? manualMaterialCost;
  final double? manualContractorEstimate;
  final double? manualLabourWorkmanship;
  final double? manualManagementFee;
  final String? manuallyEditedBy;
  final DateTime? manuallyEditedAt;
  
  // Convenience getters for UI data-binding
  double get cement => (estimatedMaterials['cement']?['quantity'] as num?)?.toDouble() ?? 0.0;
  double get bricks => (estimatedMaterials['bricks']?['quantity'] as num?)?.toDouble() ?? 0.0;
  double get steel => (estimatedMaterials['steel']?['quantity'] as num?)?.toDouble() ?? 0.0;
  double get sand => (estimatedMaterials['sand']?['quantity'] as num?)?.toDouble() ?? 0.0;
  double get aggregate => (estimatedMaterials['aggregate']?['quantity'] as num?)?.toDouble() ?? 0.0;

  EstimateModel({
    required this.estimateId,
    required this.generatedAt,
    required this.cadFileName,
    required this.geometryData,
    required this.estimatedMaterials,
    this.interiorMaterials,
    this.estimationType,
    this.materialSpecs,
    required this.confidence,
    this.labour,
    this.totalLabourDays,
    this.disclaimer,
    this.assumptions,
    this.manualMaterialCost,
    this.manualContractorEstimate,
    this.manualLabourWorkmanship,
    this.manualManagementFee,
    this.manuallyEditedBy,
    this.manuallyEditedAt,
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
          : (json['materials'] != null
              ? Map<String, Map<String, dynamic>>.from(
                  (json['materials'] as Map)['materials'] ?? json['materials'])
              : {}),
      interiorMaterials: json['interiorMaterials'] != null
          ? Map<String, dynamic>.from(json['interiorMaterials'])
          : null,
      estimationType: json['estimationType'] as String?,
      materialSpecs: json['materialSpecs'] != null
          ? Map<String, dynamic>.from(json['materialSpecs'])
          : null,
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
      manualMaterialCost: json['manualMaterialCost'] != null 
          ? (json['manualMaterialCost'] as num).toDouble() 
          : null,
      manualContractorEstimate: json['manualContractorEstimate'] != null 
          ? (json['manualContractorEstimate'] as num).toDouble() 
          : null,
      manualLabourWorkmanship: json['manualLabourWorkmanship'] != null 
          ? (json['manualLabourWorkmanship'] as num).toDouble() 
          : null,
      manualManagementFee: json['manualManagementFee'] != null 
          ? (json['manualManagementFee'] as num).toDouble() 
          : null,
      manuallyEditedBy: json['manuallyEditedBy'] as String?,
      manuallyEditedAt: json['manuallyEditedAt'] != null 
          ? (json['manuallyEditedAt'] as Timestamp).toDate() 
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
      'interiorMaterials': interiorMaterials,
      'estimationType': estimationType,
      'materialSpecs': materialSpecs,
      'confidence': confidence.name,
      'labour': labour,
      'totalLabourDays': totalLabourDays,
      'disclaimer': disclaimer,
      'assumptions': assumptions,
      'manualMaterialCost': manualMaterialCost,
      'manualContractorEstimate': manualContractorEstimate,
      'manualLabourWorkmanship': manualLabourWorkmanship,
      'manualManagementFee': manualManagementFee,
      'manuallyEditedBy': manuallyEditedBy,
      'manuallyEditedAt': manuallyEditedAt != null ? Timestamp.fromDate(manuallyEditedAt!) : null,
    };
  }
}
