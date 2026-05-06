import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_model.dart';
import '../models/user_model.dart';
import '../services/project_service.dart';
import '../providers/auth_provider.dart';

// Service provider (legacy compatibility)
final projectServiceProvider = Provider<ProjectService>((ref) => ProjectService());
final projectListProvider = StreamProvider.autoDispose<List<ProjectModel>>((ref) {
  final userProfile = ref.watch(userProfileProvider).value;
  if (userProfile == null) return Stream.value([]);

  Query query = FirebaseFirestore.instance.collection('projects');

  // Role-based filtering
  if (userProfile.role == UserRole.engineer) {
    // Only show projects where this engineer is a team member
    query = query.where('teamMembers', arrayContains: userProfile.uid);
  } else if (userProfile.role == UserRole.manager) {
    // Managers can see all projects to facilitate collaboration
    // (No filter applied)
  } else if (userProfile.role == UserRole.owner) {
    // Only show the specific project assigned to this owner
    if (userProfile.assignedProjectId != null) {
      query = query.where('projectId', isEqualTo: userProfile.assignedProjectId);
    } else {
      // If no project is assigned, return empty list stream for security
      return Stream.value([]);
    }
  }
  // Admin role sees all (no extra filter)

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

final projectByIdProvider = StreamProvider.family<ProjectModel?, String>((ref, id) {
  return FirebaseFirestore.instance
      .collection('projects')
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? ProjectModel.fromJson(snap.data()!) : null);
});

// For Engineer Home Site Selection
final selectedProjectIdProvider = StateProvider<String?>((ref) => null);
