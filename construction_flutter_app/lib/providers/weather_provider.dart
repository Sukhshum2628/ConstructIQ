import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather_model.dart';
import '../services/weather_service.dart';
import '../providers/project_provider.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

/// Current weather for a specific project (by project location).
final projectWeatherProvider = FutureProvider.autoDispose
    .family<WeatherData?, String>((ref, projectId) async {
  final project = ref.watch(projectByIdProvider(projectId)).value;
  if (project == null) return null;

  final service = ref.read(weatherServiceProvider);
  return service.getCurrentWeatherByCity(project.location);
});

/// 5-day forecast for a specific project.
final projectForecastProvider = FutureProvider.autoDispose
    .family<List<ForecastItem>, String>((ref, projectId) async {
  final project = ref.watch(projectByIdProvider(projectId)).value;
  if (project == null) return [];

  final service = ref.read(weatherServiceProvider);
  return service.get5DayForecastByCity(project.location);
});

/// Dashboard weather — uses the first active project's location.
final dashboardWeatherProvider = FutureProvider.autoDispose<WeatherData?>((ref) async {
  final projects = ref.watch(projectListProvider).value ?? [];
  if (projects.isEmpty) return null;

  final firstProject = projects.first;
  final service = ref.read(weatherServiceProvider);
  return service.getCurrentWeatherByCity(firstProject.location);
});

/// Dashboard forecast — uses the first active project's location.
final dashboardForecastProvider = FutureProvider.autoDispose<List<ForecastItem>>((ref) async {
  final projects = ref.watch(projectListProvider).value ?? [];
  if (projects.isEmpty) return [];

  final firstProject = projects.first;
  final service = ref.read(weatherServiceProvider);
  return service.get5DayForecastByCity(firstProject.location);
});
