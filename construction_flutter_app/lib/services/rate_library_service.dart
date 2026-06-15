import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rate_library.dart';

/// Loads/saves a project's editable rate library. Defaults live in code
/// (`RateLibrary.defaults`); only per-project overrides are persisted, at
/// `projects/{id}/settings/rateLibrary`.
class RateLibraryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String projectId) => _db
      .collection('projects')
      .doc(projectId)
      .collection('settings')
      .doc('rateLibrary');

  Future<RateLibrary> load(String projectId) async {
    try {
      final snap = await _doc(projectId).get();
      final overrides = snap.data()?['overrides'] as Map<String, dynamic>?;
      return RateLibrary.fromOverrides(overrides);
    } catch (_) {
      return RateLibrary.defaults();
    }
  }

  Future<void> save(String projectId, RateLibrary library) async {
    await _doc(projectId).set(
      {
        'overrides': library.toOverridesJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

final rateLibraryServiceProvider =
    Provider<RateLibraryService>((ref) => RateLibraryService());

/// The effective (defaults + overrides) rate library for a project.
final projectRateLibraryProvider =
    FutureProvider.family<RateLibrary, String>((ref, projectId) {
  return ref.watch(rateLibraryServiceProvider).load(projectId);
});
