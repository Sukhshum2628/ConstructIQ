import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cost_adjustments.dart';

/// Loads/saves a project's cost adjustments at
/// `projects/{id}/settings/costAdjustments`.
class CostAdjustmentsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String projectId) => _db
      .collection('projects')
      .doc(projectId)
      .collection('settings')
      .doc('costAdjustments');

  Future<CostAdjustments> load(String projectId) async {
    try {
      final snap = await _doc(projectId).get();
      return CostAdjustments.fromJson(snap.data());
    } catch (_) {
      return const CostAdjustments();
    }
  }

  Future<void> save(String projectId, CostAdjustments adj) async {
    await _doc(projectId).set(adj.toJson(), SetOptions(merge: true));
  }
}

final costAdjustmentsServiceProvider =
    Provider<CostAdjustmentsService>((ref) => CostAdjustmentsService());

final projectCostAdjustmentsProvider =
    FutureProvider.family<CostAdjustments, String>((ref, projectId) {
  return ref.watch(costAdjustmentsServiceProvider).load(projectId);
});
