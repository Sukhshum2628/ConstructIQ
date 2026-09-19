import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_model.dart';
import '../models/user_model.dart';
import '../services/project_service.dart';
import '../providers/auth_provider.dart';
import '../constants/demo_data.dart';
import '../utils/exceptions.dart';

// Service provider (legacy compatibility)
final projectServiceProvider = Provider<ProjectService>((ref) => ProjectService());

bool isManagerLevelRole(UserRole role) {
  return role == UserRole.manager || role == UserRole.admin;
}

final projectListProvider = StreamProvider.autoDispose<List<ProjectModel>>((ref) {
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    return Stream.value(kDemoProjectModels);
  }

  final userProfile = ref.watch(currentUserProfileProvider);
  if (userProfile == null) return Stream.value([]);

  // Strict Fail-Closed Check: If user profile has no company assigned, throw exception.
  // Never proceed to an unfiltered query across companies!
  final companyId = userProfile.companyId.trim();
  if (companyId.isEmpty) {
    throw const UnassignedCompanyException('User has no company assigned');
  }

  // Keep alive to prevent stream rebuilding on tab/screen navigation
  ref.keepAlive();

  // Root isolation: Scope strictly to the user's company
  Query query = FirebaseFirestore.instance
      .collection('projects')
      .where('companyId', isEqualTo: companyId);

  // Role-based filtering within company boundary
  if (userProfile.role == UserRole.owner) {
    // Only show projects where this user is the registered Owner
    query = query.where('ownerUserId', isEqualTo: userProfile.uid);
  } else if (userProfile.role == UserRole.engineer) {
    // Only show projects where this engineer is a team member
    query = query.where('teamMembers', arrayContains: userProfile.uid);
  }
  // Manager and admin roles can see all company projects.

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
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) {
    try {
      final match = kDemoProjectModels.firstWhere((p) => p.projectId == id);
      return Stream.value(match);
    } catch (_) {
      return Stream.value(kDemoProjectModels.first);
    }
  }

  return FirebaseFirestore.instance
      .collection('projects')
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? ProjectModel.fromJson(snap.data()!) : null);
});

final projectAccessProvider = FutureProvider.autoDispose.family<bool, String>((ref, projectId) async {
  final isDemo = ref.watch(isDemoModeProvider);
  if (isDemo) return true;

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
