import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site_report_model.dart';

class SiteReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String projectId) =>
      _db.collection('projects').doc(projectId).collection('siteReports');

  Future<void> save(SiteReportModel r) =>
      _col(r.projectId).doc(r.id).set(r.toJson(), SetOptions(merge: true));

  Future<void> delete(String projectId, String id) =>
      _col(projectId).doc(id).delete();

  Future<void> setStatus(String projectId, String id, ReportStatus status) =>
      _col(projectId).doc(id).set({
        'status': status.name,
        'resolvedAt':
            status == ReportStatus.resolved ? Timestamp.now() : null,
      }, SetOptions(merge: true));
}

final siteReportServiceProvider = Provider((ref) => SiteReportService());
