import 'package:cloud_firestore/cloud_firestore.dart';

enum ProjectStatus { planning, active, completed, onhold }
enum EstimationStatus { pending, processing, completed, failed }

class ProjectModel {
  final String projectId;
  final String name;
  final String location;
  final DateTime startDate;
  final DateTime expectedEndDate;
  final ProjectStatus status;
  final String createdBy;
  final List<String> teamMembers;
  final double plannedBudget;
  final String projectType;
  final String cadFileUrl;
  final EstimationStatus estimationStatus;
  final DateTime createdAt;
  final String? ownerUserId;
  final int durationDays;
  final double totalWallLength;
  final double totalFloorArea;

  // Getters for UI compatibility
  String get id => projectId;

  ProjectModel({
    required this.projectId,
    required this.name,
    required this.location,
    required this.startDate,
    required this.expectedEndDate,
    required this.status,
    required this.createdBy,
    required this.teamMembers,
    required this.plannedBudget,
    required this.projectType,
    required this.cadFileUrl,
    required this.estimationStatus,
    required this.createdAt,
    this.ownerUserId,
    this.durationDays = 360,
    this.totalWallLength = 0.0,
    this.totalFloorArea = 0.0,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      location: json['location'] as String,
      startDate: (json['startDate'] as Timestamp).toDate(),
      expectedEndDate: (json['expectedEndDate'] as Timestamp).toDate(),
      status: ProjectStatus.values.firstWhere((e) => e.name == json['status']),
      createdBy: json['createdBy'] as String,
      teamMembers: List<String>.from(json['teamMembers'] ?? []),
      plannedBudget: (json['plannedBudget'] as num).toDouble(),
      projectType: json['projectType'] as String,
      cadFileUrl: json['cadFileUrl'] as String,
      estimationStatus: EstimationStatus.values.firstWhere((e) => e.name == json['estimationStatus']),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      ownerUserId: json['ownerUserId'] as String?,
      durationDays: json['durationDays'] as int? ?? 360,
      totalWallLength: (json['totalWallLength'] as num? ?? 0.0).toDouble(),
      totalFloorArea: (json['totalFloorArea'] as num? ?? 0.0).toDouble(),
    );
  }

  ProjectModel copyWith({
    String? projectId,
    String? name,
    String? location,
    DateTime? startDate,
    DateTime? expectedEndDate,
    ProjectStatus? status,
    String? createdBy,
    List<String>? teamMembers,
    double? plannedBudget,
    String? projectType,
    String? cadFileUrl,
    EstimationStatus? estimationStatus,
    DateTime? createdAt,
    String? ownerUserId,
    int? durationDays,
    double? totalWallLength,
    double? totalFloorArea,
  }) {
    return ProjectModel(
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      expectedEndDate: expectedEndDate ?? this.expectedEndDate,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      teamMembers: teamMembers ?? this.teamMembers,
      plannedBudget: plannedBudget ?? this.plannedBudget,
      projectType: projectType ?? this.projectType,
      cadFileUrl: cadFileUrl ?? this.cadFileUrl,
      estimationStatus: estimationStatus ?? this.estimationStatus,
      createdAt: createdAt ?? this.createdAt,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      durationDays: durationDays ?? this.durationDays,
      totalWallLength: totalWallLength ?? this.totalWallLength,
      totalFloorArea: totalFloorArea ?? this.totalFloorArea,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectId': projectId,
      'name': name,
      'location': location,
      'startDate': Timestamp.fromDate(startDate),
      'expectedEndDate': Timestamp.fromDate(expectedEndDate),
      'status': status.name,
      'createdBy': createdBy,
      'teamMembers': teamMembers,
      'plannedBudget': plannedBudget,
      'projectType': projectType,
      'cadFileUrl': cadFileUrl,
      'estimationStatus': estimationStatus.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'ownerUserId': ownerUserId,
      'durationDays': durationDays,
      'totalWallLength': totalWallLength,
      'totalFloorArea': totalFloorArea,
    };
  }
}
