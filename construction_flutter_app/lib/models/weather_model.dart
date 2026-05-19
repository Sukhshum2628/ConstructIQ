/// Weather data models for high-fidelity keyless API responses.

class WeatherData {
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final int weatherCode;      // WMO Weather interpretation code
  final String condition;     // Human readable string mapped from code
  final String description;   
  final String iconCode;      // Simplified icon mapping
  final DateTime timestamp;
  final String cityName;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.weatherCode,
    required this.condition,
    required this.description,
    required this.iconCode,
    required this.timestamp,
    required this.cityName,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json, {String? cityName}) {
    // ── wttr.in WWO format check ──
    if (json.containsKey('current_condition')) {
      final currentList = json['current_condition'] as List;
      if (currentList.isNotEmpty) {
        final current = currentList[0] as Map<String, dynamic>;
        
        final rawCode = int.tryParse(current['weatherCode']?.toString() ?? '113') ?? 113;
        final wmoCode = _mapWwoToWmo(rawCode);
        final mapping = _mapWmoCode(wmoCode);
        
        final temp = double.tryParse(current['temp_C']?.toString() ?? '25.0') ?? 25.0;
        final feels = double.tryParse(current['FeelsLikeC']?.toString() ?? temp.toString()) ?? temp;
        final humid = int.tryParse(current['humidity']?.toString() ?? '50') ?? 50;
        final wind = double.tryParse(current['windspeedKmph']?.toString() ?? '0.0') ?? 0.0;
        
        String conditionText = mapping['label']!;
        if (current.containsKey('weatherDesc')) {
          final descList = current['weatherDesc'] as List;
          if (descList.isNotEmpty) {
            conditionText = descList[0]['value']?.toString()?.trim() ?? mapping['label']!;
          }
        }
        
        return WeatherData(
          temperature: temp,
          feelsLike: feels,
          humidity: humid,
          windSpeed: wind,
          weatherCode: wmoCode,
          condition: mapping['label']!,
          description: conditionText,
          iconCode: mapping['icon']!,
          timestamp: DateTime.now(),
          cityName: cityName ?? 'Site Location',
        );
      }
    }

    // ── Open-Meteo fallback format ──
    final current = json['current'] ?? json;
    final int code = (current['weather_code'] ?? current['weathercode'] ?? 0) as int;
    final mapping = _mapWmoCode(code);

    return WeatherData(
      temperature: (current['temperature_2m'] ?? current['temp'] ?? 0.0).toDouble(),
      feelsLike: (current['apparent_temperature'] ?? current['temp'] ?? 0.0).toDouble(),
      humidity: (current['relative_humidity_2m'] ?? 50).toInt(),
      windSpeed: (current['wind_speed_10m'] ?? 0.0).toDouble(),
      weatherCode: code,
      condition: mapping['label']!,
      description: mapping['description']!,
      iconCode: mapping['icon']!,
      timestamp: DateTime.now(),
      cityName: cityName ?? 'Site Location',
    );
  }

  /// Checks if the current weather is considered adverse for construction.
  bool get isAdverse {
    return (weatherCode >= 51 && weatherCode <= 67) || // Drizzle & Rain
           (weatherCode >= 71 && weatherCode <= 86) || // Snow & Ice
           (weatherCode >= 95 && weatherCode <= 99);   // Thunderstorms
  }

  /// Maps API condition to our internal weather label.
  String get appCategory => condition;

  static int _mapWwoToWmo(int wwoCode) {
    switch (wwoCode) {
      case 113: return 0; // Clear/Sunny
      case 116:
      case 119:
      case 122: return 1; // Cloudy/Partly Cloudy/Overcast
      case 143:
      case 248:
      case 260: return 45; // Foggy/Mist
      case 176:
      case 263:
      case 266:
      case 293:
      case 296:
      case 302:
      case 305:
      case 308:
      case 353:
      case 356: return 61; // Rainy
      case 386:
      case 389:
      case 392:
      case 395: return 95; // Stormy
      default:
        if (wwoCode >= 350 && wwoCode <= 399) return 95;
        if (wwoCode >= 200 && wwoCode <= 349) return 61;
        return 1;
    }
  }

  static Map<String, String> _mapWmoCode(int code) {
    if (code == 0) return {'label': 'Sunny', 'description': 'Clear sky', 'icon': '01d'};
    if (code >= 1 && code <= 3) return {'label': 'Cloudy', 'description': 'Mainly clear, partly cloudy, and overcast', 'icon': '03d'};
    if (code == 45 || code == 48) return {'label': 'Foggy', 'description': 'Fog and depositing rime fog', 'icon': '50d'};
    if (code >= 51 && code <= 55) return {'label': 'Rainy', 'description': 'Drizzle: Light, moderate, and dense intensity', 'icon': '09d'};
    if (code >= 61 && code <= 65) return {'label': 'Rainy', 'description': 'Rain: Slight, moderate and heavy intensity', 'icon': '10d'};
    if (code >= 71 && code <= 77) return {'label': 'Stormy', 'description': 'Snow fall: Slight, moderate, and heavy intensity', 'icon': '13d'};
    if (code >= 80 && code <= 82) return {'label': 'Rainy', 'description': 'Rain showers: Slight, moderate, and violent', 'icon': '09d'};
    if (code >= 85 && code <= 86) return {'label': 'Stormy', 'description': 'Snow showers slight and heavy', 'icon': '13d'};
    if (code >= 95 && code <= 99) return {'label': 'Stormy', 'description': 'Thunderstorm: Slight, moderate, and with heavy hail', 'icon': '11d'};
    return {'label': 'Cloudy', 'description': 'Unknown', 'icon': '03d'};
  }

  String get iconUrl => 'https://openweathermap.org/img/wn/$iconCode@2x.png';
}

class ForecastItem {
  final DateTime dateTime;
  final double tempMin;
  final double tempMax;
  final int weatherCode;
  final String condition;
  final String description;
  final String iconCode;

  ForecastItem({
    required this.dateTime,
    required this.tempMin,
    required this.tempMax,
    required this.weatherCode,
    required this.condition,
    required this.description,
    required this.iconCode,
  });

  factory ForecastItem.fromDailyJson(Map<String, dynamic> daily, int index) {
    // ── wttr.in WWO daily format check ──
    if (daily.containsKey('date') && daily.containsKey('maxtempC')) {
      final rawDate = daily['date']?.toString() ?? DateTime.now().toIso8601String();
      final tempMin = double.tryParse(daily['mintempC']?.toString() ?? '20.0') ?? 20.0;
      final tempMax = double.tryParse(daily['maxtempC']?.toString() ?? '30.0') ?? 30.0;
      
      int rawCode = 113;
      String descText = 'Sunny';
      if (daily.containsKey('hourly')) {
        final hourlyList = daily['hourly'] as List;
        final midIndex = hourlyList.length > 4 ? 4 : (hourlyList.length ~/ 2);
        if (hourlyList.isNotEmpty) {
          final hourData = hourlyList[midIndex] as Map<String, dynamic>;
          rawCode = int.tryParse(hourData['weatherCode']?.toString() ?? '113') ?? 113;
          if (hourData.containsKey('weatherDesc')) {
            final descList = hourData['weatherDesc'] as List;
            if (descList.isNotEmpty) {
              descText = descList[0]['value']?.toString()?.trim() ?? 'Sunny';
            }
          }
        }
      }
      
      final wmoCode = WeatherData._mapWwoToWmo(rawCode);
      final mapping = WeatherData._mapWmoCode(wmoCode);
      
      return ForecastItem(
        dateTime: DateTime.tryParse(rawDate) ?? DateTime.now(),
        tempMin: tempMin,
        tempMax: tempMax,
        weatherCode: wmoCode,
        condition: mapping['label']!,
        description: descText,
        iconCode: mapping['icon']!,
      );
    }

    // ── Open-Meteo fallback format ──
    final int code = (daily['weather_code'][index] as num).toInt();
    final mapping = WeatherData._mapWmoCode(code);

    return ForecastItem(
      dateTime: DateTime.parse(daily['time'][index]),
      tempMin: (daily['temperature_2m_min'][index] as num).toDouble(),
      tempMax: (daily['temperature_2m_max'][index] as num).toDouble(),
      weatherCode: code,
      condition: mapping['label']!,
      description: mapping['description']!,
      iconCode: mapping['icon']!,
    );
  }

  String get iconUrl => 'https://openweathermap.org/img/wn/$iconCode@2x.png';

  bool get isAdverse {
    return (weatherCode >= 51 && weatherCode <= 67) || 
           (weatherCode >= 71 && weatherCode <= 86) || 
           (weatherCode >= 95 && weatherCode <= 99);
  }
}
