import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirestoreSeeder {
  static final _db = FirebaseFirestore.instance;

  static Future<void> seedAll() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final uid = currentUser.uid;

    // Get real engineers to assign
    final engineersSnap = await _db.collection('users').where('role', isEqualTo: 'engineer').limit(5).get();
    final engineerUids = engineersSnap.docs.map((d) => d.id).toList();

    // Get an owner to assign to Project 1
    final ownersSnap = await _db.collection('users').where('role', isEqualTo: 'owner').limit(1).get();
    final ownerUid = ownersSnap.docs.isNotEmpty ? ownersSnap.docs.first.id : null;

    // ── PROJECT 1 ── Residential Complex
    final p1Ref = _db.collection('projects').doc('project_demo_001');
    await p1Ref.set({
      'projectId': 'project_demo_001',
      'name': 'Block-A Residential Complex',
      'location': 'Sector 7, Jammu',
      'startDate': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 90))),
      'expectedEndDate': Timestamp.fromDate(DateTime.now().add(Duration(days: 90))),
      'status': 'active',
      'createdBy': uid,
      'teamMembers': [uid, ...engineerUids.take(2)],
      'plannedBudget': 4500000.0,
      'projectType': 'residential',
      'cadFileUrl': '',
      'estimationStatus': 'completed',
      'createdAt': Timestamp.now(),
      'ownerUserId': ownerUid,
    });

    await p1Ref.collection('estimates').doc('est_001').set({
      'estimateId': 'est_001',
      'generatedAt': Timestamp.now(),
      'cadFileName': 'block_a_ground_floor.dxf',
      'geometryData': {'totalWallArea': 342.6, 'totalFloorArea': 186.4, 'totalColumnCount': 12},
      'estimatedMaterials': {
        'cement': {'quantity': 1240, 'unit': 'bags'},
        'bricks': {'quantity': 17130, 'unit': 'nos'},
        'steel': {'quantity': 4390, 'unit': 'kg'},
      },
      'labour': {
        'brick_masonry': { 'labour_days': 43, 'trade': 'Mason', 'norm_source': 'CPWD' },
        'rcc_concrete':  { 'labour_days': 19,  'trade': 'Labourer', 'norm_source': 'CPWD' },
        'steel_fixing':  { 'labour_days': 22,  'trade': 'Steel fixer', 'norm_source': 'CPWD' },
        'plastering':    { 'labour_days': 31, 'trade': 'Plasterer', 'norm_source': 'CPWD' },
      },
      'totalLabourDays': 115,
      'disclaimer': 'Labour estimates use CPWD standard productivity norms. Actual requirements vary by team size, skill level, and site conditions.',
      'confidence': 'high',
    });

    await p1Ref.collection('deviations').doc('dev_001').set({
      'deviationId': 'dev_001',
      'generatedAt': Timestamp.now(),
      'overallSeverity': 'normal',
      'mlOverrunProbability': 0.12,
      'aiInsightSummary': 'Project is stable. Minor variance in Cement consumption (+2.4%).',
      'deviations': {
        'cement': {'deviationPct': 2.4, 'severity': 'normal'},
        'bricks': {'deviationPct': -0.5, 'severity': 'normal'},
        'steel': {'deviationPct': 1.2, 'severity': 'normal'},
      }
    });

    // ── PROJECT 2 ── Highway Bridge (NH-44)
    final p2Ref = _db.collection('projects').doc('project_demo_002');
    await p2Ref.set({
      'projectId': 'project_demo_002',
      'name': 'NH-44 Highway Bridge Section',
      'location': 'Nagrota, Jammu',
      'startDate': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 120))),
      'expectedEndDate': Timestamp.fromDate(DateTime.now().add(Duration(days: 60))),
      'status': 'active',
      'createdBy': uid,
      'teamMembers': [uid, ...engineerUids.skip(1).take(2)],
      'plannedBudget': 12850000.0,
      'projectType': 'infrastructure',
      'cadFileUrl': '',
      'estimationStatus': 'completed',
      'createdAt': Timestamp.now(),
    });

    await p2Ref.collection('estimates').doc('est_002').set({
      'estimateId': 'est_002',
      'generatedAt': Timestamp.now(),
      'cadFileName': 'nh44_bridge_v2.dxf',
      'geometryData': {'bridgeLength': 150.0, 'pierCount': 4, 'deckArea': 1800.0},
      'estimatedMaterials': {
        'cement': {'quantity': 5640, 'unit': 'bags'},
        'bricks': {'quantity': 44500, 'unit': 'nos'},
        'steel': {'quantity': 26523, 'unit': 'kg'},
      },
      'labour': {
        'brick_masonry': { 'labour_days': 111, 'trade': 'Mason', 'norm_source': 'CPWD' },
        'rcc_concrete':  { 'labour_days': 180,  'trade': 'Labourer', 'norm_source': 'CPWD' },
        'steel_fixing':  { 'labour_days': 133,  'trade': 'Steel fixer', 'norm_source': 'CPWD' },
      },
      'totalLabourDays': 424,
      'disclaimer': 'Labour estimates use CPWD standard productivity norms. Actual requirements vary by team size, skill level, and site conditions.',
      'confidence': 'medium',
    });

    await p2Ref.collection('deviations').doc('dev_002').set({
      'deviationId': 'dev_002',
      'generatedAt': Timestamp.now(),
      'overallSeverity': 'critical',
      'mlOverrunProbability': 0.89,
      'aiInsightSummary': 'CRITICAL: Severe material overruns in Cement (+62.5%) and Steel (+60.0%) during bridge pier reinforcement.',
      'deviations': {
        'cement': {'deviationPct': 62.5, 'severity': 'critical'},
        'bricks': {'deviationPct': 4.2, 'severity': 'normal'},
        'steel': {'deviationPct': 60.0, 'severity': 'critical'},
      }
    });

    // ── PROJECT 3 ── Smart City Office Block
    final p3Ref = _db.collection('projects').doc('project_demo_003');
    await p3Ref.set({
      'projectId': 'project_demo_003',
      'name': 'Smart City Office Block',
      'location': 'Gandhi Nagar, Jammu',
      'startDate': Timestamp.fromDate(DateTime.now().subtract(Duration(days: 30))),
      'expectedEndDate': Timestamp.fromDate(DateTime.now().add(Duration(days: 270))),
      'status': 'active',
      'createdBy': uid,
      'teamMembers': [uid, ...engineerUids.skip(2).take(2)],
      'plannedBudget': 8200000.0,
      'projectType': 'commercial',
      'cadFileUrl': '',
      'estimationStatus': 'completed',
      'createdAt': Timestamp.now(),
    });

    // ADDED MISSING ESTIMATE FOR PROJECT 3
    await p3Ref.collection('estimates').doc('est_003').set({
      'estimateId': 'est_003',
      'generatedAt': Timestamp.now(),
      'cadFileName': 'smart_city_office.dxf',
      'geometryData': {'officeArea': 4500.0, 'floors': 5, 'columnCount': 24},
      'estimatedMaterials': {
        'cement': {'quantity': 3200, 'unit': 'bags'},
        'bricks': {'quantity': 25000, 'unit': 'nos'},
        'steel': {'quantity': 8500, 'unit': 'kg'},
      },
      'labour': {
        'brick_masonry': { 'labour_days': 63, 'trade': 'Mason', 'norm_source': 'CPWD' },
        'steel_fixing':  { 'labour_days': 43,  'trade': 'Steel fixer', 'norm_source': 'CPWD' },
        'plastering':    { 'labour_days': 45, 'trade': 'Plasterer', 'norm_source': 'CPWD' },
      },
      'totalLabourDays': 151,
      'disclaimer': 'Labour estimates use CPWD standard productivity norms. Actual requirements vary by team size, skill level, and site conditions.',
      'confidence': 'high',
    });

    // Logs for Project 3
    final logs3 = [
      {'cement': 24, 'bricks': 860, 'steel': 125, 'daysAgo': 2},
      {'cement': 26, 'bricks': 870, 'steel': 130, 'daysAgo': 1},
      {'cement': 25, 'bricks': 865, 'steel': 128, 'daysAgo': 0},
    ];

    await _clearCollection(p3Ref.collection('resourceLogs'));
    for (var log in logs3) {
      final daysAgo = log['daysAgo'] as int;
      final logDate = DateTime.now().subtract(Duration(days: daysAgo));
      await p3Ref.collection('resourceLogs').doc('day_$daysAgo').set({
        'logId': 'log_p3_day_$daysAgo', 'loggedBy': uid, 'logDate': Timestamp.fromDate(logDate),
        'materials': {'cement': log['cement'], 'bricks': log['bricks'], 'steel': log['steel']},
        'createdAt': Timestamp.fromDate(logDate),
      });
    }

    await p3Ref.collection('deviations').doc('dev_003').set({
      'deviationId': 'dev_003',
      'generatedAt': Timestamp.now(),
      'overallSeverity': 'warning',
      'mlOverrunProbability': 0.35,
      'aiInsightSummary': 'MODERATE: Cement consumption is 35.7% above estimate. Review masonry work efficiency.',
      'deviations': {
        'cement': {'deviationPct': 35.7, 'severity': 'warning'},
        'bricks': {'deviationPct': 12.4, 'severity': 'normal'},
        'steel': {'deviationPct': -2.1, 'severity': 'normal'},
      }
    });
    
    // Seed Profile Data...
    await _db.collection('users').doc(uid).update({
      'designation': 'Project Director',
    });
    
    // Seed WORKFORCE
    await _seedWorkforce();

    debugPrint('✅ Firestore seeded: 3 projects with workforce, records, and profile updates');
  }

  static Future<void> _seedWorkforce() async {
    final projects = ['project_demo_001', 'project_demo_002', 'project_demo_003'];
    final trades = ['mason', 'laborer', 'helper', 'carpenter', 'steelFixer'];
    final names = ['Ramesh Kumar', 'Suresh Singh', 'Abdul Khan', 'Vijay Sharma', 'Deepak Verma', 'Sunil Dutt', 'Rajesh Gupta', 'Manoj Yadv', 'Amit Shah', 'Pawan Kalyan'];

    for (var pid in projects) {
      for (int i = 0; i < 8; i++) {
        final wid = "worker_\${pid}_\$i";
        final trade = trades[i % trades.length];
        await _db.collection('workforce').doc(wid).set({
          'id': wid,
          'name': names[i % names.length],
          'trade': trade,
          'contact': '+91 90000 1000\$i',
          'status': 'active',
          'assignedProjectId': pid,
          'dailyRate': trade == 'mason' ? 800.0 : 450.0,
        });

        // Seed 1 record for today for first 5 workers
        if (i < 5) {
          final today = DateTime.now();
          final startOfDay = DateTime(today.year, today.month, today.day);
          final aid = "\${wid}_\$i";
          await _db.collection('attendance').doc(aid).set({
            'id': aid,
            'workerId': wid,
            'projectId': pid,
            'date': Timestamp.fromDate(startOfDay),
            'status': 'present',
            'markedBy': 'system',
            'checkIn': Timestamp.fromDate(today),
          });
        }
      }
    }
  }

  static Future<void> _clearCollection(CollectionReference ref) async {
    final snapshots = await ref.get();
    for (final doc in snapshots.docs) {
      await doc.reference.delete();
    }
  }
}
