import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_model.dart';
import '../services/ml_predictor_service.dart';

/// Provider that holds the ML predictor service singleton.
/// Auto-initialises the model on first access.
final mlPredictorProvider = Provider.autoDispose<MLPredictorService>((ref) {
  final service = mlPredictorService;

  // Load model asynchronously on first provider access
  service.loadModel();

  // Dispose when provider is removed
  ref.onDispose(() => service.dispose());

  return service;
});

/// Input data class for the overrun prediction
class OverrunPredictionInput {
  final double materialDeviationAvg;
  final double equipmentIdleRatio;
  final double daysElapsedPct;
  final double budgetSize;
  final int projectTypeEncoded;

  const OverrunPredictionInput({
    required this.materialDeviationAvg,
    required this.equipmentIdleRatio,
    required this.daysElapsedPct,
    required this.budgetSize,
    required this.projectTypeEncoded,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverrunPredictionInput &&
          runtimeType == other.runtimeType &&
          materialDeviationAvg == other.materialDeviationAvg &&
          equipmentIdleRatio == other.equipmentIdleRatio &&
          daysElapsedPct == other.daysElapsedPct &&
          budgetSize == other.budgetSize &&
          projectTypeEncoded == other.projectTypeEncoded;

  @override
  int get hashCode =>
      materialDeviationAvg.hashCode ^
      equipmentIdleRatio.hashCode ^
      daysElapsedPct.hashCode ^
      budgetSize.hashCode ^
      projectTypeEncoded.hashCode;
}

/// FutureProvider that computes on-device ML prediction from deviation data.
final onDeviceOverrunProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, OverrunPredictionInput>((ref, input) async {
  final predictor = ref.watch(mlPredictorProvider);

  return predictor.predictOverrun(
    materialDeviationAvg: input.materialDeviationAvg,
    equipmentIdleRatio: input.equipmentIdleRatio,
    daysElapsedPct: input.daysElapsedPct,
    budgetSize: input.budgetSize,
    projectTypeEncoded: input.projectTypeEncoded,
  );
});

/// Map projectType string to model-supported integer
int encodeProjectType(String type) {
  switch (type.toLowerCase()) {
    case 'residential': return 0;
    case 'commercial': return 1;
    case 'infrastructure': return 2;
    default: return 0;
  }
}

/// Calculate fraction of time elapsed in the project
double calculateDaysElapsedPct(DateTime start, DateTime end) {
  final now = DateTime.now();
  if (now.isBefore(start)) return 0.0;
  if (now.isAfter(end)) return 1.0;
  
  final totalDuration = end.difference(start).inDays;
  if (totalDuration <= 0) return 1.0;
  
  final elapsed = now.difference(start).inDays;
  return (elapsed / totalDuration).clamp(0.0, 1.0);
}

/// Helper to extract average deviation from Firestore map
double getMaterialDeviationAvg(Map<String, dynamic> deviations) {
  if (deviations.isEmpty) return 0.0;
  
  double sum = 0.0;
  int count = 0;
  
  deviations.forEach((key, value) {
    if (value is Map && value.containsKey('deviationPct')) {
      sum += (value['deviationPct'] as num).toDouble();
      count++;
    }
  });
  
  if (count == 0) return 0.0;
  return (sum / count) / 100.0; // Convert 2.4% to 0.024
}

