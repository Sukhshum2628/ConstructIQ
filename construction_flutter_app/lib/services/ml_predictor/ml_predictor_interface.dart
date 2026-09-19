import 'dart:async';

abstract class MLPredictorServiceBase {
  Future<void> loadModel();
  Future<double> predictOverrunProbability(List<double> features);
  Future<Map<String, dynamic>> predictOverrun({
    required double materialDeviationAvg,
    required double equipmentIdleRatio,
    required double daysElapsedPct,
    required double budgetSize,
    required int projectTypeEncoded,
  });
  void dispose();
}
