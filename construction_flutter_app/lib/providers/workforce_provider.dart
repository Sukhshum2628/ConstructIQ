import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workforce_model.dart';

import 'auth_provider.dart';
import '../constants/demo_data.dart';

final workforceByProjectProvider = FutureProvider.autoDispose.family<List<WorkerModel>, String>((ref, projectId) async {
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    return kDemoWorkforce;
  }

  final snap = await FirebaseFirestore.instance
      .collection('workforce')
      .where('assignedProjectId', isEqualTo: projectId)
      .get();
  
  return snap.docs.map((doc) => WorkerModel.fromJson(doc.data())).toList();
});

class WorkforceService {
  // Methods for worker registration/management can go here
}

final workforceServiceProvider = Provider((ref) => WorkforceService());
