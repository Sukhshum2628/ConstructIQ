import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather_model.dart';
import '../services/weather_service.dart';
import '../providers/project_provider.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

/// Current weather for a specific project (by project location).
/// Current weather for a specific project (by project location).
final projectWeatherProvider = FutureProvider
    .family<WeatherData?, String>((ref, projectId) async {
  final project = await ref.watch(projectByIdProvider(projectId).future);
  if (project == null) return null;

  final service = ref.read(weatherServiceProvider);
  return service.getCurrentWeatherByCity(project.location);
});

/// 5-day forecast for a specific project.
final projectForecastProvider = FutureProvider
    .family<List<ForecastItem>, String>((ref, projectId) async {
  final project = await ref.watch(projectByIdProvider(projectId).future);
  if (project == null) return [];

  final service = ref.read(weatherServiceProvider);
  return service.get5DayForecastByCity(project.location);
});

/// Dashboard weather — uses selected project or first available.
final dashboardWeatherProvider = FutureProvider<WeatherData?>((ref) async {
  final projects = await ref.watch(projectListProvider.future);
  if (projects.isEmpty) return null;

  final selectedId = ref.watch(selectedDashboardProjectIdProvider);
  final project = selectedId != null 
      ? projects.firstWhere((p) => p.projectId == selectedId, orElse: () => projects.first)
      : projects.first;

  print('DEBUG: Weather Provider - Fetching for: ${project.name} (${project.location})');
  final service = ref.read(weatherServiceProvider);
  return service.getCurrentWeatherByCity(project.location);
});

/// Dashboard forecast — uses selected project or first available.
final dashboardForecastProvider = FutureProvider<List<ForecastItem>>((ref) async {
  final projects = await ref.watch(projectListProvider.future);
  if (projects.isEmpty) return [];

  final selectedId = ref.watch(selectedDashboardProjectIdProvider);
  final project = selectedId != null 
      ? projects.firstWhere((p) => p.projectId == selectedId, orElse: () => projects.first)
      : projects.first;

  final service = ref.read(weatherServiceProvider);
  return service.get5DayForecastByCity(project.location);
});
