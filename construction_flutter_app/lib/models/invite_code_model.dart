import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

class InviteCodeModel {
  final String code;
  final String companyId;
  final UserRole role;
  final String createdBy;
  final int maxUses;
  final int usesSoFar;
  final bool isActive;
  final DateTime? expiresAt;
  final DateTime createdAt;

  InviteCodeModel({
    required this.code,
    required this.companyId,
    required this.role,
    required this.createdBy,
    this.maxUses = 1,
    this.usesSoFar = 0,
    this.isActive = true,
    this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isExhausted => usesSoFar >= maxUses;

  bool get isValid => isActive && !isExpired && !isExhausted;

  factory InviteCodeModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value, {required DateTime fallback}) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return fallback;
    }

    return InviteCodeModel(
      code: json['code'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.engineer,
      ),
      createdBy: json['createdBy'] as String? ?? '',
      maxUses: json['maxUses'] as int? ?? 1,
      usesSoFar: json['usesSoFar'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      expiresAt: json['expiresAt'] != null
          ? parseDate(json['expiresAt'], fallback: DateTime.now())
          : null,
      createdAt: parseDate(json['createdAt'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'companyId': companyId,
      'role': role.name,
      'createdBy': createdBy,
      'maxUses': maxUses,
      'usesSoFar': usesSoFar,
      'isActive': isActive,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
