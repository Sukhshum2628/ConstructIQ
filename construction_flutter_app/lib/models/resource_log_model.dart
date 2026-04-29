import 'package:cloud_firestore/cloud_firestore.dart';

class EquipmentEntry {
  final String name;
  final double usedHours;
  final double idleHours;

  EquipmentEntry({
    required this.name,
    required this.usedHours,
    required this.idleHours,
  });

  factory EquipmentEntry.fromJson(Map<String, dynamic> json) {
    return EquipmentEntry(
      name: json['name'] as String? ?? 'Unknown',
      usedHours: (json['usedHours'] as num? ?? 0.0).toDouble(),
      idleHours: (json['idleHours'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'usedHours': usedHours,
      'idleHours': idleHours,
    };
  }
}

class ResourceLogModel {
  final String id;
  final String projectId;
  final String loggedBy;
  final DateTime date;
  final Map<String, double> materialUsage;
  final List<EquipmentEntry> equipmentList;
  final double laborHours;
  final String notes;
  final String weatherCondition;
  final bool isWeatherDelay;
  final String? photoUrl;
  final Map<String, double>? location;
  final DateTime createdAt;

  ResourceLogModel({
    required this.id,
    required this.projectId,
    required this.loggedBy,
    required this.date,
    required this.materialUsage,
    required this.equipmentList,
    required this.laborHours,
    required this.notes,
    required this.weatherCondition,
    this.isWeatherDelay = false,
    this.photoUrl,
    this.location,
    required this.createdAt,
  });

  // Aliases for Service/JSON compatibility
  String get logId => id;
  DateTime get logDate => date;
  Map<String, double> get materials => materialUsage;
  
  // Backward compatibility getter
  Map<String, Map<String, double>> get equipment {
    return {
      for (var e in equipmentList) 
        e.name: {'usedHours': e.usedHours, 'idleHours': e.idleHours}
    };
  }

  factory ResourceLogModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    // Handle both old Map format and new List format
    List<EquipmentEntry> parsedEquipment = [];
    final eqData = json['equipment'];
    
    if (eqData is List) {
       parsedEquipment = eqData.map((e) => EquipmentEntry.fromJson(e as Map<String, dynamic>)).toList();
    } else if (eqData is Map) {
      // Legacy Map format: { "Excavator": { "usedHours": 5, "idleHours": 2 } }
      eqData.forEach((key, value) {
        if (value is Map) {
          parsedEquipment.add(EquipmentEntry(
            name: key,
            usedHours: (value['usedHours'] as num? ?? 0.0).toDouble(),
            idleHours: (value['idleHours'] as num? ?? 0.0).toDouble(),
          ));
        }
      });
    }

    return ResourceLogModel(
      id: docId ?? json['id'] as String? ?? json['logId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      loggedBy: json['loggedBy'] as String? ?? 'Unknown',
      date: (json['date'] as Timestamp?)?.toDate() ?? 
            (json['logDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      materialUsage: Map<String, double>.from(json['materialUsage'] ?? json['materials'] ?? {}),
      equipmentList: parsedEquipment,
      laborHours: (json['laborHours'] as num? ?? 0.0).toDouble(),
      notes: json['notes'] as String? ?? '',
      weatherCondition: json['weatherCondition'] as String? ?? 'Sunny',
      isWeatherDelay: json['isWeatherDelay'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
      location: json['location'] != null ? Map<String, double>.from(json['location']) : null,
      createdAt: (json['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'loggedBy': loggedBy,
      'date': Timestamp.fromDate(date),
      'materialUsage': materialUsage,
      'equipment': equipmentList.map((e) => e.toJson()).toList(),
      'laborHours': laborHours,
      'notes': notes,
      'weatherCondition': weatherCondition,
      'isWeatherDelay': isWeatherDelay,
      'photoUrl': photoUrl,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
