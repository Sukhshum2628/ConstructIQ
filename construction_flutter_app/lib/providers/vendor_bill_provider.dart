import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/vendor_bill_service.dart';
import '../models/vendor_bill_model.dart';
import 'project_provider.dart';
import 'auth_provider.dart';

final vendorBillServiceProvider = Provider<VendorBillService>((ref) {
  return VendorBillService();
});

final projectBillsProvider = StreamProvider.autoDispose.family<List<VendorBillModel>, String>((ref, projectId) {
  // Watch auth state to handle reactive invalidation/cleanup on logout
  final authState = ref.watch(authStateChangesProvider);
  if (authState.value == null) {
    return Stream.value([]);
  }

  // Keep alive to prevent lag on scroll
  ref.keepAlive();

  return ref.watch(vendorBillServiceProvider).getProjectBills(projectId);
});

// For Owner Dashboard (Recent across all owned projects)
final ownerRecentBillsProvider = StreamProvider.autoDispose<List<VendorBillModel>>((ref) {
  final projectsAsync = ref.watch(userProjectsProvider);
  
  return projectsAsync.when(
    data: (projects) {
      if (projects.isEmpty) return Stream.value([]);
      final projectIds = projects.map((p) => p.projectId).toList();
      return ref.watch(vendorBillServiceProvider).getRecentBillsAcrossProjects(projectIds);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

final invoicedTotalProvider = Provider.autoDispose.family<double, String>((ref, projectId) {
  final billsAsync = ref.watch(projectBillsProvider(projectId));
  return billsAsync.maybeWhen(
    data: (bills) => bills.fold(0.0, (sum, b) => sum + b.amount),
    orElse: () => 0.0,
  );
});

final materialsReceivedProvider = Provider.autoDispose.family<Map<String, double>, String>((ref, projectId) {
  final billsAsync = ref.watch(projectBillsProvider(projectId));
  return billsAsync.maybeWhen(
    data: (bills) {
      final received = <String, double>{};
      for (final bill in bills) {
        for (final item in bill.items) {
          final desc = item.description.toLowerCase();
          final String key;
          if (desc.contains('cement')) key = 'cement';
          else if (desc.contains('brick')) key = 'bricks';
          else if (desc.contains('sand')) key = 'sand';
          else if (desc.contains('steel') || desc.contains('rebar')) key = 'steel';
          else key = desc;

          received[key] = (received[key] ?? 0) + item.quantity;
        }
      }
      return received;
    },
    orElse: () => <String, double>{},
  );
});
