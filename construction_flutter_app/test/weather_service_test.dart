import 'package:flutter_test/flutter_test.dart';
import 'package:construction_app/services/weather_service.dart';
import 'package:construction_app/models/weather_model.dart';

void main() {
  group('Weather Verification & Auditing Tests', () {
    late WeatherService weatherService;

    setUp(() {
      weatherService = WeatherService();
    });

    test('verifyUserClaim returns true for exact matching weather conditions', () {
      final sunnyWeather = WeatherData(
        temperature: 30.0,
        feelsLike: 32.0,
        humidity: 45,
        windSpeed: 8.0,
        weatherCode: 0, // Sunny
        condition: 'Sunny',
        description: 'Clear sky',
        iconCode: '01d',
        timestamp: DateTime.now(),
        cityName: 'Jammu',
      );

      // Engineer selects Sunny, API says Sunny
      final result = weatherService.verifyUserClaim('Sunny', sunnyWeather);
      expect(result, isTrue);
    });

    test('verifyUserClaim returns true for interchangeable Rainy and Stormy weather conditions', () {
      final rainyWeather = WeatherData(
        temperature: 18.0,
        feelsLike: 18.0,
        humidity: 90,
        windSpeed: 25.0,
        weatherCode: 61, // Rainy
        condition: 'Rainy',
        description: 'Moderate rain',
        iconCode: '10d',
        timestamp: DateTime.now(),
        cityName: 'Noida',
      );

      // Engineer selects Stormy (adverse), API says Rainy (adverse)
      final result1 = weatherService.verifyUserClaim('Stormy', rainyWeather);
      expect(result1, isTrue);

      final stormyWeather = WeatherData(
        temperature: 15.0,
        feelsLike: 14.0,
        humidity: 95,
        windSpeed: 40.0,
        weatherCode: 95, // Stormy
        condition: 'Stormy',
        description: 'Severe thunderstorm',
        iconCode: '11d',
        timestamp: DateTime.now(),
        cityName: 'Noida',
      );

      // Engineer selects Rainy (adverse), API says Stormy (adverse)
      final result2 = weatherService.verifyUserClaim('Rainy', stormyWeather);
      expect(result2, isTrue);
    });

    test('verifyUserClaim returns false for distinct mismatching weather claims', () {
      final sunnyWeather = WeatherData(
        temperature: 32.0,
        feelsLike: 34.0,
        humidity: 40,
        windSpeed: 5.0,
        weatherCode: 0,
        condition: 'Sunny',
        description: 'Clear sky',
        iconCode: '01d',
        timestamp: DateTime.now(),
        cityName: 'Delhi',
      );

      // Engineer claims Rainy, but API reports Sunny weather
      final result = weatherService.verifyUserClaim('Rainy', sunnyWeather);
      expect(result, isFalse);
    });

    test('WeatherData.isAdverse correctly flags rain/storm codes and lets clear skies pass', () {
      // Sunny should not be flagged as adverse
      final sunny = WeatherData(
        temperature: 28.0, feelsLike: 28.0, humidity: 50, windSpeed: 5.0,
        weatherCode: 0, condition: 'Sunny', description: 'Clear', iconCode: '01d',
        timestamp: DateTime.now(), cityName: 'Pune',
      );
      expect(sunny.isAdverse, isFalse);

      // Rainy WMO Code (61) must be adverse
      final rainy = WeatherData(
        temperature: 19.0, feelsLike: 19.0, humidity: 85, windSpeed: 12.0,
        weatherCode: 61, condition: 'Rainy', description: 'Rain', iconCode: '10d',
        timestamp: DateTime.now(), cityName: 'Pune',
      );
      expect(rainy.isAdverse, isTrue);

      // Stormy WMO Code (95) must be adverse
      final stormy = WeatherData(
        temperature: 16.0, feelsLike: 15.0, humidity: 90, windSpeed: 35.0,
        weatherCode: 95, condition: 'Stormy', description: 'Thunderstorm', iconCode: '11d',
        timestamp: DateTime.now(), cityName: 'Pune',
      );
      expect(stormy.isAdverse, isTrue);
    });

    test('WeatherData.fromJson parses wttr.in current_condition format accurately', () {
      final mockWttrJson = {
        'current_condition': [
          {
            'temp_C': '26',
            'FeelsLikeC': '28',
            'humidity': '52',
            'windspeedKmph': '14',
            'weatherCode': '113', // Clear/Sunny
            'weatherDesc': [
              {'value': 'Sunny'}
            ]
          }
        ]
      };

      final parsed = WeatherData.fromJson(mockWttrJson, cityName: 'Mumbai');

      expect(parsed.temperature, equals(26.0));
      expect(parsed.feelsLike, equals(28.0));
      expect(parsed.humidity, equals(52));
      expect(parsed.windSpeed, equals(14.0));
      expect(parsed.condition, equals('Sunny'));
      expect(parsed.cityName, equals('Mumbai'));
    });
  });
}
