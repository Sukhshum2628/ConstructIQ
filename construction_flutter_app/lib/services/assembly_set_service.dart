import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/assembly.dart';

/// Loads/saves a project's editable assembly recipes. Defaults live in code
/// (`AssemblySet.defaults`); only per-project coefficient overrides are
/// persisted, at `projects/{id}/settings/assemblies`.
class AssemblySetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String projectId) => _db
      .collection('projects')
      .doc(projectId)
      .collection('settings')
      .doc('assemblies');

  Future<AssemblySet> load(String projectId) async {
    try {
      final snap = await _doc(projectId).get();
      final overrides = snap.data()?['overrides'] as Map<String, dynamic>?;
      return AssemblySet.fromOverrides(overrides);
    } catch (_) {
      return AssemblySet.defaults();
    }
  }

  Future<void> save(String projectId, AssemblySet set) async {
    await _doc(projectId).set(
      {
        'overrides': set.toOverridesJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

final assemblySetServiceProvider =
    Provider<AssemblySetService>((ref) => AssemblySetService());

final projectAssemblySetProvider =
    FutureProvider.family<AssemblySet, String>((ref, projectId) {
  return ref.watch(assemblySetServiceProvider).load(projectId);
});
