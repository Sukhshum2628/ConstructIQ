import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';

class AiService {
  final Dio _dio = Dio();
  final String _baseUrl = AppConstants.apiBaseUrl;

  Future<Map<String, dynamic>> queryAi(String projectId, String question) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/rag/query',
        data: {
          'projectId': projectId,
          'message': question, // Consistent with ChatRequest Pydantic model
          'user_id': FirebaseAuth.instance.currentUser?.uid,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      return response.data;
    } catch (e) {
      throw Exception('AI Assistant query failed: $e');
    }
  }

  Future<String> getChatResponse(String message, {String? projectId}) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/rag/query',
        data: {
          'projectId': projectId ?? 'general',
          'message': message,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      if (response.statusCode == 200) {
        return response.data['reply'];
      }
      throw Exception('Chat failed');
    } catch (e) {
      throw Exception('AI error: $e');
    }
  }

  /// Calls the stateful LangGraph Project Analyst agent. It decides which
  /// project tools to query (schedule, cost, logs, weather) and returns a
  /// synthesised answer plus the tools it used. Slower than RAG (multi-step),
  /// so the timeout is generous.
  Future<Map<String, dynamic>> analyzeProject(
      String projectId, String question) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/agent/analyze',
        data: {'project_id': projectId, 'question': question},
        options: Options(
          headers: {'Authorization': 'Bearer $idToken'},
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      throw Exception('Project analysis failed: $e');
    }
  }

  Future<void> indexProject(String projectId) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      await _dio.post(
        '$_baseUrl/api/rag/index',
        data: {'project_id': projectId},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
    } catch (e) {
      throw Exception('Project indexing failed: $e');
    }
  }
}
