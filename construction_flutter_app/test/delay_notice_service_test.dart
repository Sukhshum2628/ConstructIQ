import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/services/delay_notice_service.dart';

void main() {
  test('managerRespond approves and updates expectedEndDate and durationDays', () async {
    final fakeFirestore = FakeFirebaseFirestore();

    // Setup: create a project with startDate and expectedEndDate
    final projectId = 'proj_test';
    final startDate = DateTime(2024, 1, 1);
    final expectedEnd = DateTime(2024, 10, 1); // 274 days

    await fakeFirestore.collection('projects').doc(projectId).set({
      'projectId': projectId,
      'startDate': Timestamp.fromDate(startDate),
      'expectedEndDate': Timestamp.fromDate(expectedEnd),
      'durationDays': expectedEnd.difference(startDate).inDays,
    });

    // Create a dummy delay notice
    final noticeId = 'notice1';
    await fakeFirestore
        .collection('projects')
        .doc(projectId)
        .collection('delayNotices')
        .doc(noticeId)
        .set({
      'id': noticeId,
      'projectId': projectId,
      'title': 'Test delay',
      'description': 'Materials late',
      'affectedMaterials': ['cement'],
      'expectedDeliveryDate': Timestamp.fromDate(DateTime(2024, 5, 1)),
      'reportedDate': Timestamp.fromDate(DateTime.now()),
      'createdBy': 'eng1',
      'createdByName': 'Eng One',
      'status': 'approved',
      'votes': {},
      'requiredVoters': [],
      'managerResponse': null,
    });

    final service = DelayNoticeService(db: fakeFirestore);

    // Act: manager approves with 30 days extension
    await service.managerRespond(
      projectId: projectId,
      noticeId: noticeId,
      decision: 'approved',
      daysExtended: 30,
      notes: 'Approve 30 days',
      managerId: 'mgr1',
    );

    // Assert: project doc updated
    final projSnap = await fakeFirestore.collection('projects').doc(projectId).get();
    final projData = projSnap.data()!;
    final newEndTs = projData['expectedEndDate'] as Timestamp;
    final newDuration = projData['durationDays'] as int;

    expect(newEndTs.toDate(), expectedEnd.add(Duration(days: 30)));
    expect(newDuration, equals(expectedEnd.add(Duration(days: 30)).difference(startDate).inDays));

    // Also assert notice updated
    final noticeSnap = await fakeFirestore
        .collection('projects')
        .doc(projectId)
        .collection('delayNotices')
        .doc(noticeId)
        .get();
    final noticeData = noticeSnap.data()!;
    expect(noticeData['status'], 'acknowledged_extended');
    expect(noticeData['managerResponse'] != null, true);
    expect(noticeData['managerResponse']['decision'], 'approved');
    expect(noticeData['managerResponse']['daysExtended'], 30);
  });
}
