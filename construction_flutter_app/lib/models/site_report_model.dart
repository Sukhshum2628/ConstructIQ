import 'package:cloud_firestore/cloud_firestore.dart';

enum SiteReportType { incident, snag }

enum ReportSeverity { low, medium, high }

enum ReportStatus { open, inProgress, resolved }

/// A site safety incident or a quality snag / punch-list item.
class SiteReportModel {
  final String id;
  final String projectId;
  final SiteReportType type;
  final String title;
  final String description;
  final ReportSeverity severity; // mainly for incidents
  final ReportStatus status;
  final String location;
  final String? photoUrl;
  final String reportedBy;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  SiteReportModel({
    required this.id,
    required this.projectId,
    required this.type,
    required this.title,
    this.description = '',
    this.severity = ReportSeverity.medium,
    this.status = ReportStatus.open,
    this.location = '',
    this.photoUrl,
    required this.reportedBy,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isResolved => status == ReportStatus.resolved;

  factory SiteReportModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    return SiteReportModel(
      id: docId ?? json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      type: SiteReportType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SiteReportType.snag,
      ),
      title: json['title'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      severity: ReportSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => ReportSeverity.medium,
      ),
      status: ReportStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ReportStatus.open,
      ),
      location: json['location'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      reportedBy: json['reportedBy'] as String? ?? '',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (json['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'type': type.name,
        'title': title,
        'description': description,
        'severity': severity.name,
        'status': status.name,
        'location': location,
        'photoUrl': photoUrl,
        'reportedBy': reportedBy,
        'createdAt': Timestamp.fromDate(createdAt),
        'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      };
}
