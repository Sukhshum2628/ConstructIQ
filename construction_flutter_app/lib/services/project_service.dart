import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project_model.dart';

import 'package:firebase_auth/firebase_auth.dart';
import '../utils/exceptions.dart';

class ProjectService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createProject(ProjectModel project) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw Exception('User record not found');

      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null || companyId.trim().isEmpty) {
        throw const UnassignedCompanyException('User has no company assigned to create projects');
      }

      final projectData = {
        ...project.toJson(),
        'companyId': companyId.trim(), // Authoritative server stamp
      };

      await _db.collection('projects').doc(project.projectId).set(projectData);
    } catch (e) {
      throw Exception('Project creation failed: $e');
    }
  }

  Stream<List<ProjectModel>> getProjects() {
    return _db.collection('projects').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ProjectModel.fromJson(doc.data())).toList();
    });
  }

  Future<ProjectModel?> getProjectById(String id) async {
    try {
      final doc = await _db.collection('projects').doc(id).get();
      if (doc.exists) {
        return ProjectModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch project: $e');
    }
  }

  Future<void> updateProject(ProjectModel project) async {
    try {
      await _db.collection('projects').doc(project.projectId).update(project.toJson());
    } catch (e) {
      throw Exception('Project update failed: $e');
    }
  }

  Future<void> deleteProject(String projectId) async {
    try {
      final projectRef = _db.collection('projects').doc(projectId);

      // Recursive cleanup of standard sub-collections
      await _deleteCollection(projectRef.collection('estimates'));
      await _deleteCollection(projectRef.collection('deviations'));
      await _deleteCollection(projectRef.collection('resourceLogs'));

      // Finally delete the project document itself
      await projectRef.delete();
    } catch (e) {
      throw Exception('Project deletion failed: $e');
    }
  }

  /// Helper to delete all documents in a collection (non-recursive for simplicity)
  Future<void> _deleteCollection(CollectionReference ref) async {
    final snapshots = await ref.get();
    for (final doc in snapshots.docs) {
      await doc.reference.delete();
    }
  }
}
