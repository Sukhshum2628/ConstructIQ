import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/resource_log_service.dart';
import '../models/resource_log_model.dart';

final loggingServiceProvider = Provider<ResourceLogService>((ref) {
  return ResourceLogService();
});

final projectLogsProvider = StreamProvider.autoDispose.family<List<ResourceLogModel>, String>((ref, projectId) {
  return ref.watch(loggingServiceProvider).getLogs(projectId);
});

/// Count of resource logs queued offline and awaiting sync.
final pendingSyncCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(loggingServiceProvider).pendingCount();
});
