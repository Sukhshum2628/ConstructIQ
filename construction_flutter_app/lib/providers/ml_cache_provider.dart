import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/deviation_model.dart';

class MlCacheState {
  final Map<String, double> predictions;     // projectId -> probability
  final Map<String, String> severities;      // projectId -> severity string
  final Map<String, DeviationResult> results; // projectId -> full DeviationResult
  final Set<String> loading;                 // projectIds currently computing
  final Set<String> computed;                // projectIds already done

  const MlCacheState({
    this.predictions = const {},
    this.severities = const {},
    this.results = const {},
    this.loading = const {},
    this.computed = const {},
  });

  MlCacheState copyWith({
    Map<String, double>? predictions,
    Map<String, String>? severities,
    Map<String, DeviationResult>? results,
    Set<String>? loading,
    Set<String>? computed,
  }) => MlCacheState(
    predictions: predictions ?? this.predictions,
    severities: severities ?? this.severities,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    computed: computed ?? this.computed,
  );
}

class MlCacheNotifier extends Notifier<MlCacheState> {
  @override
  MlCacheState build() {
    ref.keepAlive();  // Keep alive so cache survives navigation (FIX 4)
    return const MlCacheState();
  }

  bool isComputed(String projectId) =>
      state.computed.contains(projectId);

  bool isLoading(String projectId) =>
      state.loading.contains(projectId);

  double? getPrediction(String projectId) =>
      state.predictions[projectId];

  DeviationResult? getResult(String projectId) =>
      state.results[projectId];

  void markLoading(String projectId) {
    state = state.copyWith(
      loading: {...state.loading, projectId},
    );
  }

  void setResult(String projectId, double probability, String severity, DeviationResult result) {
    final newPredictions = Map<String, double>.from(state.predictions);
    final newSeverities = Map<String, String>.from(state.severities);
    final newResults = Map<String, DeviationResult>.from(state.results);
    final newLoading = Set<String>.from(state.loading)..remove(projectId);
    final newComputed = {...state.computed, projectId};

    newPredictions[projectId] = probability;
    newSeverities[projectId] = severity;
    newResults[projectId] = result;

    state = state.copyWith(
      predictions: newPredictions,
      severities: newSeverities,
      results: newResults,
      loading: newLoading,
      computed: newComputed,
    );
  }

  void setError(String projectId) {
    final newLoading = Set<String>.from(state.loading)..remove(projectId);
    final newPredictions = Map<String, double>.from(state.predictions);
    newPredictions[projectId] = 0.0;
    state = state.copyWith(
      loading: newLoading,
      predictions: newPredictions,
      computed: {...state.computed, projectId},
    );
  }

  // Call this when project data changes (new logs added)
  void invalidate(String projectId) {
    final newComputed = Set<String>.from(state.computed)..remove(projectId);
    state = state.copyWith(computed: newComputed);
  }
}

final mlCacheProvider = NotifierProvider<MlCacheNotifier, MlCacheState>(
  MlCacheNotifier.new,
);
