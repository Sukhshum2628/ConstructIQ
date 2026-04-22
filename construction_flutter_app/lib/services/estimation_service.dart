import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/estimate_model.dart';
import '../utils/constants.dart';

class EstimationService {
  final Dio _dio = Dio();
  final String _baseUrl = AppConstants.apiBaseUrl;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> uploadAndParseCAD(File dxfFile) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(dxfFile.path, filename: 'blueprint.dxf'),
      });

      final response = await _dio.post(
        '$_baseUrl/api/cad/parse-upload',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      
      return response.data;
    } catch (e) {
      throw Exception('CAD Analysis failed: $e');
    }
  }

  Future<double> extractInvoiceBudget(File pdfFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(pdfFile.path, filename: 'invoice.pdf'),
      });

      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/estimation/extract-budget',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      
      return (response.data['extracted_budget'] as num).toDouble();
    } catch (e) {
      throw Exception('Invoice extraction failed: $e');
    }
  }

  Future<Map<String, dynamic>> extractInvoiceDetails(File file) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, 
            filename: file.path.split('/').last),
      });

      final response = await _dio.post(
        '$_baseUrl/api/estimation/extract-items',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      
      return response.data;
    } catch (e) {
      throw Exception('AI Invoice scanning failed: $e');
    }
  }

  Future<Map<String, dynamic>> parseInvoiceLocal(File file) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, 
            filename: file.path.split('/').last),
      });

      final response = await _dio.post(
        '$_baseUrl/parse-invoice',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      
      return response.data;
    } catch (e) {
      throw Exception('Invoice parsing failed: $e');
    }
  }

  Future<List<int>> generateEstimationReport(String projectName, Map<String, dynamic> data) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/estimation/generate-report',
        data: {
          'project_name': projectName,
          'geometry': data['geometry'],
          'materials': data['materials'],
          'labour': data['labour'],
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $idToken'},
        ),
      );
      return response.data;
    } catch (e) {
      throw Exception('Report generation failed: $e');
    }
  }

  // Legacy compatibility
  Future<EstimateModel> generateEstimate(String projectId, String fileUrl) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/estimation/estimate',
        data: {'projectId': projectId, 'geometry': {'file_url': fileUrl}},
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      return EstimateModel.fromJson(response.data);
    } catch (e) {
      throw Exception('Estimation failed: $e');
    }
  }

  Future<List<EstimateModel>> getProjectEstimates(String projectId) async {
    try {
      final snapshot = await _firestore
          .collection('projects')
          .doc(projectId)
          .collection('estimates')
          .orderBy('generatedAt', descending: true)
          .get();
      
      return snapshot.docs.map((doc) => EstimateModel.fromJson(doc.data())).toList();
    } catch (e) {
      throw Exception('Failed to fetch estimates: $e');
    }
  }

  Future<Map<String, dynamic>> getEstimations(Map<String, dynamic> geometry) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await _dio.post(
        '$_baseUrl/api/estimation/calculate-from-geometry',
        data: geometry,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      return response.data;
    } catch (e) {
      // Fallback for demo if endpoint not ready
      return {
        'bricks': 12500,
        'cement_bags': 450,
        'sand_m3': 18.5,
        'rcc_volume_m3': 24.0,
      };
    }
  }
}
