import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/resource_log_model.dart';

class ResourceLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _queueKey = 'offline_log_queue';

  Future<void> addLog(ResourceLogModel log) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    Map<String, dynamic> logData = log.toJson();
    final projectId = log.projectId;

    if (connectivityResult.contains(ConnectivityResult.none)) {
      await _queueLogLocally(logData);
      return;
    }

    try {
      await _db
          .collection('projects')
          .doc(projectId)
          .collection('resourceLogs')
          .add(logData);
    } catch (e) {
      await _queueLogLocally(logData);
    }
  }

  Future<void> _queueLogLocally(Map<String, dynamic> logData) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    queue.add(jsonEncode(logData));
    await prefs.setStringList(_queueKey, queue);
  }

  Future<void> processQueue() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (var item in queue) {
      try {
        final data = jsonDecode(item);
        final pId = data['projectId'];
        await _db.collection('projects')
            .doc(pId)
            .collection('resourceLogs')
            .add(data);
      } catch (e) {
        remaining.add(item);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
  }

  Stream<List<ResourceLogModel>> getLogs(String projectId) {
    return _db.collection('projects').doc(projectId).collection('resourceLogs')
        .orderBy('date', descending: true)
        .snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ResourceLogModel.fromJson(doc.data(), doc.id)).toList();
    });
  }
}
