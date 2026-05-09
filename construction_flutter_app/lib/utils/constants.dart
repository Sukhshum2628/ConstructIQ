import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Construction AI';
  static const Color primaryColor = Colors.indigo;
  
  // Storage Keys
  static const String userRoleKey = 'user_role';
  
  // API Endpoints
  static const String apiBaseUrl = String.fromEnvironment(
    'PYTHON_SERVICE_URL',
    defaultValue: 'https://YOUR-SERVICE.railway.app',
  );

  // Google Sign-In
  static const String googleClientId = '999147799724-ai5qed4irvuve5q0bp7s0ugclhq4s7i8.apps.googleusercontent.com';
}
