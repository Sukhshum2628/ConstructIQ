import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_model.dart';
import '../models/user_model.dart';
import '../services/project_service.dart';
import '../providers/auth_provider.dart';

// Service provider (legacy compatibility)
final projectServiceProvider = Provider<ProjectService>((ref) => ProjectService());

bool isManagerLevelRole(UserRole role) {
  return role == UserRole.manager || role == UserRole.admin || role == UserRole.owner;
}

final projectListProvider = StreamProvider.autoDispose<List<ProjectModel>>((ref) {
  final userProfile = ref.watch(currentUserProfileProvider);
  if (userProfile == null) return Stream.value([]);

  Query query = FirebaseFirestore.instance.collection('projects');

  // Role-based filtering
  if (userProfile.role == UserRole.engineer) {
    // Only show projects where this engineer is a team member
    query = query.where('teamMembers', arrayContains: userProfile.uid);
  }
  // Manager, admin, and owner roles can see all projects.

  return query
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => ProjectModel.fromJson(doc.data() as Map<String, dynamic>))
          .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

// Alias for UI compatibility
final projectsStreamProvider = projectListProvider;
final userProjectsProvider = projectListProvider;

// Selected Project for Dashboard Context (Weather, Trends, etc.)
final selectedDashboardProjectIdProvider = StateProvider<String?>((ref) => null);

// Derived provider for dashboard summary cards
final activeProjectCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return ref.watch(projectListProvider).whenData(
    (projects) => projects.where((p) => p.status == ProjectStatus.active).length,
  );
});

final projectByIdProvider = StreamProvider.autoDispose.family<ProjectModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? ProjectModel.fromJson(snap.data()!) : null);
});

final projectAccessProvider = FutureProvider.autoDispose.family<bool, String>((ref, projectId) async {
  final userProfile = ref.watch(currentUserProfileProvider);
  if (userProfile == null) return false;

  if (isManagerLevelRole(userProfile.role)) {
    return true;
  }

  final projectDoc = await FirebaseFirestore.instance
      .collection('projects')
      .doc(projectId)
      .get();

  if (!projectDoc.exists) return false;

  final data = projectDoc.data() ?? <String, dynamic>{};
  final teamMembers = List<String>.from(data['teamMembers'] ?? const []);
  final ownerUserId = data['ownerUserId'] as String?;

  return teamMembers.contains(userProfile.uid) || ownerUserId == userProfile.uid;
});

// For Engineer Home Site Selection
final selectedProjectIdProvider = StateProvider<String?>((ref) => null);
