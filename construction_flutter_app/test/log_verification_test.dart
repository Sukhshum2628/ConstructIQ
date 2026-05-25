import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:construction_app/services/weather_service.dart';
import 'package:construction_app/models/weather_model.dart';

// Helper: Haversine formula to compute exact physical distance in meters between two coordinates.
// This matches standard geofence boundary checks in GIS and Geolocator.
double calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusInMeters = 6371000.0;
  
  double dLat = _toRadians(lat2 - lat1);
  double dLon = _toRadians(lon2 - lon1);
  
  double a = sin(dLat / 2) * sin(dLat / 2) +
             cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
             sin(dLon / 2) * sin(dLon / 2);
             
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  
  return earthRadiusInMeters * c;
}

double _toRadians(double degree) {
  return degree * (pi / 180.0);
}

void main() {
  group('1. GPS Geofence Coordinate Verification Tests', () {
    const double geofenceRadiusLimitMeters = 200.0; // 200 meters active geofence
    
    // Project location: Jammu Site (MIET Autonomous Campus)
    const double projectLat = 32.7266;
    const double projectLng = 74.8570;

    test('Engineer logging inside geofence boundary (50 meters away) is ALLOWED', () {
      // Engineer's live location captured by mobile sensor
      const double engineerLat = 32.7268; 
      const double engineerLng = 74.8573;

      double actualDistance = calculateHaversineDistance(projectLat, projectLng, engineerLat, engineerLng);
      print('DEBUG TEST: Geofence actual distance is ${actualDistance.toStringAsFixed(2)} meters.');

      bool isInsideGeofence = actualDistance <= geofenceRadiusLimitMeters;
      
      expect(isInsideGeofence, isTrue, reason: 'Actual distance should be well within the 200m limit.');
      expect(actualDistance, lessThan(100.0));
    });

    test('Engineer logging outside geofence boundary (Jammu vs Delhi - ~500km away) is REJECTED', () {
      // Engineer attempts to log remotely from New Delhi coordinates
      const double remoteLat = 28.6139;
      const double remoteLng = 77.2090;

      double actualDistance = calculateHaversineDistance(projectLat, projectLng, remoteLat, remoteLng);
      print('DEBUG TEST: Geofence remote distance is ${(actualDistance / 1000.0).toStringAsFixed(2)} kilometers.');

      bool isInsideGeofence = actualDistance <= geofenceRadiusLimitMeters;

      expect(isInsideGeofence, isFalse, reason: 'Site engineer is logged remotely, far beyond the 200m limit.');
      expect(actualDistance, greaterThan(10000.0)); // Should be > 10,000 meters away
    });
  });

  group('2. Weather Gating & Claim Verification Tests', () {
    final weatherService = WeatherService();

    test('User claims Rainy and API confirms Rainy -> Matches successfully', () {
      final mockApiWeather = WeatherData(
        cityName: 'Jammu',
        temperature: 20.0,
        feelsLike: 19.5,
        humidity: 90,
        windSpeed: 15.0,
        weatherCode: 3,
        condition: 'Rainy',
        description: 'Moderate rain showers',
        iconCode: '10d',
        timestamp: DateTime.now(),
      );

      bool isClaimValid = weatherService.verifyUserClaim('Rainy', mockApiWeather);
      expect(isClaimValid, isTrue);
    });

    test('User claims Rainy and API confirms Stormy -> Matches (Adverse weather category equivalence)', () {
      final mockApiWeather = WeatherData(
        cityName: 'Jammu',
        temperature: 18.0,
        feelsLike: 17.0,
        humidity: 95,
        windSpeed: 25.0,
        weatherCode: 4,
        condition: 'Stormy',
        description: 'Thunderstorm conditions',
        iconCode: '11d',
        timestamp: DateTime.now(),
      );

      bool isClaimValid = weatherService.verifyUserClaim('Rainy', mockApiWeather);
      expect(isClaimValid, isTrue, reason: 'Rainy and Stormy should be cross-compatible adverse log gates.');
    });

    test('User claims Sunny but API reports Rainy -> Mismatch! Alert triggers verification override dialog', () {
      final mockApiWeather = WeatherData(
        cityName: 'Jammu',
        temperature: 21.0,
        feelsLike: 20.0,
        humidity: 88,
        windSpeed: 8.0,
        weatherCode: 3,
        condition: 'Rainy',
        description: 'Light continuous rain',
        iconCode: '10d',
        timestamp: DateTime.now(),
      );

      bool isClaimValid = weatherService.verifyUserClaim('Sunny', mockApiWeather);
      expect(isClaimValid, isFalse, reason: 'A clear sunny claim contradicts active rain reported by the API.');
    });
  });
}
