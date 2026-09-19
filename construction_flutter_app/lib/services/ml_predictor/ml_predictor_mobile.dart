import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:typed_data';
import 'dart:async';
import 'ml_predictor_interface.dart';

/// On-device XGBoost cost overrun predictor using ONNX Runtime for Mobile (Android / iOS / Native).
class MLPredictorService implements MLPredictorServiceBase {
  static const String _modelAssetPath = 'assets/models/cost_overrun_model.onnx';

  OrtSession? _session;
  bool _isLoaded = false;
  Future<void>? _loadFuture;
  Future<void>? _predictionLock;

  @override
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
      final ByteData modelData = await rootBundle.load(_modelAssetPath);
      final Uint8List modelBytes = modelData.buffer.asUint8List();

      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();

      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isLoaded = true;

      debugPrint('[ML] Native ONNX model loaded successfully '
          '(${modelBytes.length ~/ 1024} KB)');
    } catch (e) {
      debugPrint('[ML] Native model failed to load: $e');
      _isLoaded = false;
    }
  }

  @override
  Future<double> predictOverrunProbability(List<double> features) async {
    try {
      if (features.isEmpty) return 0.0;
      if (features.any((f) => f.isNaN || f.isInfinite)) return 0.0;
      if (features.length != 5) {
        while (features.length < 5) {
          features.add(0.0);
        }
        features = features.take(5).toList();
      }

      if (!_isLoaded) {
        await loadModel();
      }

      if (_session == null) {
        return 0.0;
      }

      final previousLock = _predictionLock;
      final completer = Completer<void>();
      _predictionLock = completer.future;

      if (previousLock != null) {
        try {
          await previousLock;
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 50));
      }

      try {
        final inputData = Float32List.fromList(features);
        final inputTensor = OrtValueTensor.createTensorWithDataList(
          inputData,
          [1, 5],
        );

        final inputs = {'float_input': inputTensor};
        final outputs = await _session!.runAsync(
          OrtRunOptions(),
          inputs,
        );

        double probability = 0.5;

        if (outputs != null && outputs.length > 1) {
          final probOutput = outputs[1];
          if (probOutput?.value is List) {
            final probList = probOutput!.value as List;
            if (probList.isNotEmpty && probList[0] is Map) {
              final probMap = probList[0] as Map;
              probability = (probMap[1] as double?) ?? 0.5;
            } else if (probList.isNotEmpty && probList[0] is List) {
              final innerList = probList[0] as List;
              probability = innerList.length > 1
                  ? (innerList[1] as double? ?? 0.5)
                  : 0.5;
            }
          }
        }

        inputTensor.release();
        outputs?.forEach((element) => element?.release());

        debugPrint('[ML] Native on-device prediction: ${probability.toStringAsFixed(3)}');
        return probability.clamp(0.0, 1.0);
      } finally {
        completer.complete();
      }
    } catch (e, stackTrace) {
      debugPrint('ONNX inference failed: $e');
      debugPrint('[ML] ONNX inference StackTrace: $stackTrace');
      return 0.0;
    }
  }

  @override
  Future<Map<String, dynamic>> predictOverrun({
    required double materialDeviationAvg,
    required double equipmentIdleRatio,
    required double daysElapsedPct,
    required double budgetSize,
    required int projectTypeEncoded,
  }) async {
    if (!_isLoaded) {
      await loadModel();
    }

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

  Map<String, dynamic> _fallbackPrediction({
    required double materialDeviationAvg,
    required double equipmentIdleRatio,
  }) {
    final probability = (materialDeviationAvg * 0.65 +
            equipmentIdleRatio * 0.35)
        .clamp(0.0, 0.95);

    return {
      'probability': probability,
      'risk_level': _getRiskLevel(probability),
      'on_device': false,
    };
  }

  String _getRiskLevel(double probability) {
    if (probability > 0.6) return 'HIGH';
    if (probability > 0.3) return 'MEDIUM';
    return 'LOW';
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
    _isLoaded = false;
  }
}

final MLPredictorService mlPredictorService = MLPredictorService();
