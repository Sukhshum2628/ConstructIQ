import 'package:cloud_firestore/cloud_firestore.dart';

enum DelayType { weather, materialShortage, laborShortage, equipment, other }
enum DelayStatus { pending, verified, rejected, overridden }

class DelayRecord {
  final String id;
  final String projectId;
  final DelayType type;
  final String reason;
  final DateTime date;
  final int daysLost;
  final DelayStatus status;
  final String? weatherApiProof;   // JSON snapshot from API at time of claim
  final String? photoUrl;          // Mandatory photo for weather overrides
  final String recordedBy;         // UID of the person who logged it
  final DateTime createdAt;
  final String? linkedLogId;       // Optional link to the resource log

  DelayRecord({
    required this.id,
    required this.projectId,
    required this.type,
    required this.reason,
    required this.date,
    required this.daysLost,
    required this.status,
    this.weatherApiProof,
    this.photoUrl,
    required this.recordedBy,
    required this.createdAt,
    this.linkedLogId,
  });

  factory DelayRecord.fromJson(Map<String, dynamic> json, [String? docId]) {
    return DelayRecord(
      id: docId ?? json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      type: DelayType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DelayType.other,
      ),
      reason: json['reason'] as String? ?? '',
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      daysLost: json['daysLost'] as int? ?? 1,
      status: DelayStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DelayStatus.pending,
      ),
      weatherApiProof: json['weatherApiProof'] as String?,
      photoUrl: json['photoUrl'] as String?,
      recordedBy: json['recordedBy'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      linkedLogId: json['linkedLogId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'type': type.name,
      'reason': reason,
      'date': Timestamp.fromDate(date),
      'daysLost': daysLost,
      'status': status.name,
      'weatherApiProof': weatherApiProof,
      'photoUrl': photoUrl,
      'recordedBy': recordedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'linkedLogId': linkedLogId,
    };
  }

  /// Human-readable label for delay type.
  String get typeLabel {
    switch (type) {
      case DelayType.weather:
        return 'Weather';
      case DelayType.materialShortage:
        return 'Material Shortage';
      case DelayType.laborShortage:
        return 'Labor Shortage';
      case DelayType.equipment:
        return 'Equipment';
      case DelayType.other:
        return 'Other';
    }
  }

  /// Icon for delay type.
  String get typeIcon {
    switch (type) {
      case DelayType.weather:
        return '🌧️';
      case DelayType.materialShortage:
        return '📦';
      case DelayType.laborShortage:
        return '👷';
      case DelayType.equipment:
        return '🔧';
      case DelayType.other:
        return '⏳';
    }
  }
}
