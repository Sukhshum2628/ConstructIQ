import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/estimation_profile.dart';

/// Loads/saves a project's finish package + regional profile at
/// `projects/{id}/settings/estimationProfile`.
class EstimationProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String projectId) => _db
      .collection('projects')
      .doc(projectId)
      .collection('settings')
      .doc('estimationProfile');

  Future<EstimationProfile> load(String projectId) async {
    try {
      final snap = await _doc(projectId).get();
      return EstimationProfile.fromJson(snap.data());
    } catch (_) {
      return const EstimationProfile();
    }
  }

  Future<void> save(String projectId, EstimationProfile profile) async {
    await _doc(projectId).set(profile.toJson(), SetOptions(merge: true));
  }
}

final estimationProfileServiceProvider =
    Provider<EstimationProfileService>((ref) => EstimationProfileService());

final projectEstimationProfileProvider =
    FutureProvider.family<EstimationProfile, String>((ref, projectId) {
  return ref.watch(estimationProfileServiceProvider).load(projectId);
});
