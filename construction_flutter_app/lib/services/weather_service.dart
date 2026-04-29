import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather_model.dart';

/// Service for fetching weather data from Open-Meteo (Free, Keyless).
class WeatherService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _geoUrl = 'https://geocoding-api.open-meteo.com/v1/search';

  // ── Current Weather ──
  Future<WeatherData?> getCurrentWeather(double lat, double lng) async {
    try {
      final url = '$_baseUrl?latitude=$lat&longitude=$lng&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=auto';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return WeatherData.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── Current Weather by City Name ──
  Future<WeatherData?> getCurrentWeatherByCity(String cityName) async {
    try {
      final res = await _geocodeCity(cityName);
      if (res == null) return null;
      return getCurrentWeather(res['lat']!, res['lng']!);
    } catch (e) {
      return null;
    }
  }

  // ── 7-Day Forecast ──
  Future<List<ForecastItem>> get5DayForecast(double lat, double lng) async {
    try {
      final url = '$_baseUrl?latitude=$lat&longitude=$lng&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final daily = data['daily'] as Map<String, dynamic>;
        final List<ForecastItem> forecast = [];
        
        for (int i = 0; i < (daily['time'] as List).length; i++) {
          forecast.add(ForecastItem.fromDailyJson(daily, i));
        }
        
        return forecast;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── 7-Day Forecast by City Name ──
  Future<List<ForecastItem>> get5DayForecastByCity(String cityName) async {
    try {
      final res = await _geocodeCity(cityName);
      if (res == null) return [];
      return get5DayForecast(res['lat']!, res['lng']!);
    } catch (e) {
      return [];
    }
  }

  // ── Geocode a city name to lat/lng using Open-Meteo Geocoding ──
  Future<Map<String, double>?> _geocodeCity(String cityName) async {
    try {
      final cleanName = cityName.split(',').last.trim();
      final url = '$_geoUrl?name=$cleanName&count=1&language=en&format=json';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          final first = data['results'][0];
          return {
            'lat': (first['latitude'] as num).toDouble(),
            'lng': (first['longitude'] as num).toDouble(),
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── Verify user's weather claim against API ──
  bool verifyUserClaim(String userClaim, WeatherData actual) {
    final apiCategory = actual.appCategory.toLowerCase();
    final claim = userClaim.toLowerCase();

    if (claim == apiCategory) return true;

    // Rainy includes stormy in some contexts, but let's stay strict for audit
    if (claim == 'rainy' && apiCategory == 'stormy') return true;
    if (claim == 'stormy' && apiCategory == 'rainy') return true;

    return false;
  }

  /// Get raw API JSON as a string for proof storage.
  Future<String?> getWeatherProofSnapshot(double lat, double lng) async {
    try {
      final url = '$_baseUrl?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code&timezone=auto';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
