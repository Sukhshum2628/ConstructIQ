import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/deviation_model.dart';
import '../utils/constants.dart';

class DeviationService {
  final Dio _dio = Dio();
  final String _baseUrl = AppConstants.apiBaseUrl;

  Future<DeviationModel> analyzeProject(String projectId) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/analyze-deviation',
        data: {'projectId': projectId},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200) {
        return DeviationModel.fromJson(response.data);
      }
      throw Exception('Analysis failed');
    } catch (e) {
      throw Exception('Deviation analysis error: $e');
    }
  }

  Future<double> getOverrunPrediction(String projectId) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/predict-overrun',
        data: {'projectId': projectId},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      if (response.statusCode == 200) {
        return (response.data['mlOverrunProbability'] as num).toDouble();
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
}
