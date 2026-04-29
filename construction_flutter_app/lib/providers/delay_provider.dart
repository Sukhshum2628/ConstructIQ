import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delay_record_model.dart';

/// Stream of all delay records for a project, sorted by date descending.
final projectDelaysProvider = StreamProvider.autoDispose
    .family<List<DelayRecord>, String>((ref, projectId) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .collection('delays')
      .orderBy('date', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => DelayRecord.fromJson(doc.data(), doc.id))
          .toList());
});

/// Total verified delay days for a project.
final totalDelayDaysProvider = Provider.autoDispose
    .family<AsyncValue<int>, String>((ref, projectId) {
  return ref.watch(projectDelaysProvider(projectId)).whenData(
    (delays) => delays
        .where((d) => d.status == DelayStatus.verified || d.status == DelayStatus.overridden)
        .fold<int>(0, (sum, d) => sum + d.daysLost),
  );
});

/// Add a delay record and auto-extend the project timeline.
Future<void> addDelayRecord(DelayRecord record) async {
  final db = FirebaseFirestore.instance;

  // 1. Add the delay record
  await db
      .collection('projects')
      .doc(record.projectId)
      .collection('delays')
      .doc(record.id)
      .set(record.toJson());

  // 2. Auto-extend the project timeline
  if (record.status == DelayStatus.verified || record.status == DelayStatus.overridden) {
    await db.collection('projects').doc(record.projectId).update({
      'durationDays': FieldValue.increment(record.daysLost),
    });
  }
}
