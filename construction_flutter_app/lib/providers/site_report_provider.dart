import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/site_report_model.dart';

final siteReportsProvider = StreamProvider.autoDispose
    .family<List<SiteReportModel>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('siteReports')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => SiteReportModel.fromJson(d.data(), d.id))
          .toList());
});
