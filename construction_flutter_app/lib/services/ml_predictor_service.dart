import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:typed_data';
import 'dart:async';

/// On-device XGBoost cost overrun predictor using ONNX Runtime.
/// Runs entirely offline — no network call required.
/// Model: trained XGBoost classifier, AUC 0.82, 5 input features.
///
/// Feature order (must match training):
///   f0: material_deviation_avg  — average % deviation / 100
///   f1: equipment_idle_ratio    — fraction of idle hours (0.0–1.0)
///   f2: days_elapsed_pct        — project timeline completion (0.0–1.0)
///   f3: budget_size             — planned budget in lakhs (e.g. 45.0)
///   f4: project_type_encoded    — 0=residential, 1=commercial, 2=infrastructure
class MLPredictorService {
  static const String _modelAssetPath = 'assets/models/cost_overrun_model.onnx';

  OrtSession? _session;
  bool _isLoaded = false;
  Future<void>? _loadFuture;
  Future<void>? _predictionLock;

  /// Load the ONNX model from assets into memory.
  /// Call this once during app startup or on first use.
  /// The model is ~76KB so loading is near-instant.
  Future<void> loadModel() async {
    if (_isLoaded) return;
    if (_loadFuture != null) {
      return _loadFuture!;
    }

    _loadFuture = _doLoadModel();
    try {
      await _loadFuture;
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> _doLoadModel() async {
    try {
      // Load model bytes from Flutter assets
      final ByteData modelData = await rootBundle.load(_modelAssetPath);
      final Uint8List modelBytes = modelData.buffer.asUint8List();

      // Initialize ONNX Runtime session
      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();

      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isLoaded = true;

      debugPrint('[ML] On-device model loaded successfully '
          '(${modelBytes.length ~/ 1024} KB)');
    } catch (e) {
      debugPrint('[ML] Model failed to load: $e');
      _isLoaded = false;
    }
  }

  /// Predict cost overrun probability using input list directly, with complete Try-Catch wrapping
  /// and robust feature validations to avoid any native OrtSession failures (FIX 1).
  Future<double> predictOverrunProbability(List<double> features) async {
    try {
      // validate inputs before passing to ONNX
      if (features.isEmpty) {
        return 0.0;
      }
      if (features.any((f) => f.isNaN || f.isInfinite)) {
        return 0.0;
      }
      if (features.length != 5) {
        // model expects exactly 5 features
        // pad or truncate to prevent shape mismatch
        while (features.length < 5) {
          features.add(0.0);
        }
        features = features.take(5).toList();
      }

      // Ensure model is loaded
      if (!_isLoaded) {
        await loadModel();
      }

      // If model still not loaded, return 0.0
      if (_session == null) {
        return 0.0;
      }

      // FIX 3: Acquire lock to run predictions sequentially with a small delay to prevent concurrent ONNX session access
      final previousLock = _predictionLock;
      final completer = Completer<void>();
      _predictionLock = completer.future;

      if (previousLock != null) {
        try {
          await previousLock;
        } catch (_) {}
        // Small delay between predictions to prevent concurrent ONNX session access
        await Future.delayed(const Duration(milliseconds: 50));
      }

      try {
        // Build input tensor — shape [1, 5] (batch_size=1, features=5)
        final inputData = Float32List.fromList(features);

        final inputTensor = OrtValueTensor.createTensorWithDataList(
          inputData,
          [1, 5], // shape: 1 sample, 5 features
        );

        // Run inference
        final inputs = {'float_input': inputTensor};
        final outputs = await _session!.runAsync(
          OrtRunOptions(),
          inputs,
        );

        // Extract probability of class 1 (overrun = true)
        // XGBoost ONNX output[0] = predicted label, output[1] = probabilities
        double probability = 0.5; // default

        if (outputs != null && outputs.length > 1) {
          final probOutput = outputs[1]; // index 1 = probabilities
          if (probOutput?.value is List) {
            final probList = probOutput!.value as List;
            if (probList.isNotEmpty && probList[0] is Map) {
              // XGBoost ONNX format: [{0: prob_0, 1: prob_1}]
              final probMap = probList[0] as Map;
              probability = (probMap[1] as double?) ?? 0.5;
            } else if (probList.isNotEmpty && probList[0] is List) {
              // Alternative format: [[prob_0, prob_1]]
              final innerList = probList[0] as List;
              probability = innerList.length > 1
                  ? (innerList[1] as double? ?? 0.5)
                  : 0.5;
            }
          }
        }

        // Release tensors
        inputTensor.release();
        outputs?.forEach((element) => element?.release());

        debugPrint('[ML] On-device prediction: ${probability.toStringAsFixed(3)}');

        return probability.clamp(0.0, 1.0);
      } finally {
        completer.complete();
      }
    } catch (e, stackTrace) {
      debugPrint('ONNX inference failed: $e');
      debugPrint('[ML] ONNX inference StackTrace: $stackTrace');
      // Return fallback value — do not crash
      return 0.0;
    }
  }

  /// Predict cost overrun probability from project deviation features.
  ///
  /// Returns: { 'probability': double, 'risk_level': String, 'on_device': bool }
  Future<Map<String, dynamic>> predictOverrun({
    required double materialDeviationAvg,
    required double equipmentIdleRatio,
    required double daysElapsedPct,
    required double budgetSize,
    required int projectTypeEncoded,
  }) async {
    // Ensure model is loaded
    if (!_isLoaded) {
      await loadModel();
    }

    // If model still not loaded, use rule-based fallback
    if (_session == null) {
      return _fallbackPrediction(
        materialDeviationAvg: materialDeviationAvg,
        equipmentIdleRatio: equipmentIdleRatio,
      );
    }

    final features = [
      materialDeviationAvg,
      equipmentIdleRatio,
      daysElapsedPct,
      budgetSize,
      projectTypeEncoded.toDouble(),
    ];

    final probability = await predictOverrunProbability(features);

    return {
      'probability': probability,
      'risk_level': _getRiskLevel(probability),
      'on_device': true,
    };
  }

  /// Rule-based fallback when model cannot be loaded.
  Map<String, dynamic> _fallbackPrediction({
    required double materialDeviationAvg,
    required double equipmentIdleRatio,
  }) {
    // Simple weighted sum matching training feature importances
    final probability = (materialDeviationAvg * 0.65 +
            equipmentIdleRatio * 0.35)
        .clamp(0.0, 0.95);

    return {
      'probability': probability,
      'risk_level': _getRiskLevel(probability),
      'on_device': false, // signals fallback was used
    };
  }

  String _getRiskLevel(double probability) {
    if (probability > 0.6) return 'HIGH';
    if (probability > 0.3) return 'MEDIUM';
    return 'LOW';
  }

  /// Dispose ONNX session when no longer needed.
  void dispose() {
    _session?.release();
    _session = null;
    _isLoaded = false;
  }
}

// Singleton instance for app-wide use
final mlPredictorService = MLPredictorService();
