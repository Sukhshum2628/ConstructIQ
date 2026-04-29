/// Weather data models for Open-Meteo API responses.

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
    // WMO codes for rain, snow, and thunderstorms
    return (weatherCode >= 51 && weatherCode <= 67) || // Drizzle & Rain
           (weatherCode >= 71 && weatherCode <= 86) || // Snow & Ice
           (weatherCode >= 95 && weatherCode <= 99);   // Thunderstorms
  }

  /// Maps API condition to our internal weather label.
  String get appCategory => condition;

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
