import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, manager, engineer, owner }

class UserModel {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? phone;
  final String? designation;
  final List<String> assignedProjects;
  final String? assignedProjectId; // for owner role
  final DateTime createdAt;
  final DateTime lastLogin;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.designation,
    required this.assignedProjects,
    this.assignedProjectId,
    required this.createdAt,
    required this.lastLogin,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value, {required DateTime fallback}) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return fallback;
    }

    return UserModel(
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed User',
      email: json['email'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.engineer,
      ),
      phone: json['phone'] as String?,
      designation: json['designation'] as String?,
      assignedProjects: List<String>.from(json['assignedProjects'] ?? []),
      assignedProjectId: json['assignedProjectId'] as String?,
      createdAt: parseDate(json['createdAt'], fallback: DateTime.now()),
      lastLogin: parseDate(json['lastLogin'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role.name,
      'phone': phone,
      'designation': designation,
      'assignedProjects': assignedProjects,
      'assignedProjectId': assignedProjectId,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': Timestamp.fromDate(lastLogin),
    };
  }
}
