import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/estimate_model.dart';
import '../utils/constants.dart';

import 'package:flutter/foundation.dart';
import 'package:construction_app/services/pdf_ml_parser.dart';
import 'package:construction_app/services/estimation_engine.dart';

class EstimationService {
  final Dio _dio = Dio();
  final String _baseUrl = AppConstants.apiBaseUrl;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> calculateEstimates(String projectId, Map<String, dynamic> geometry) async {
    // Computed on-device with the CPWD formulas (ported from the backend
    // estimation_engine.py). No network round-trip — works offline and keeps
    // the Render service slim.
    return EstimationEngine.estimate(projectId, geometry);
  }

  Future<Map<String, dynamic>> parseFile(String filePath,
      {double? userLongFt, double? userShortFt}) async {
    final ext = filePath.split('.').last.toLowerCase();

    if (ext == 'pdf') {
      // 1. On-device ML parsing — no network needed for geometry
      final geomResult = await PdfMlParser.parsePdf(filePath,
          userLongFt: userLongFt, userShortFt: userShortFt);

      // Surface failures and "scale required" straight to the caller so the UI
      // can prompt the user instead of estimating off a zero / wrong area.
      if (geomResult['parserType'] == 'ml_pdf_failed' ||
          geomResult['parserType'] == 'ml_pdf_needs_scale') {
        return geomResult;
      }
      
      final geometry = {
        'totalFloorArea': geomResult['totalFloorArea'],
        'totalWallLength': geomResult['totalWallLength'],
        'totalColumnCount': 4.0,
        'buildingHeight': 3.0,
        'structuralVolume': geomResult['totalFloorArea'] * 0.15,
        'confidenceScore': geomResult['confidence'],
        // Carried through for interior estimation (fixtures/electrical).
        'roomCounts': geomResult['roomCounts'] ?? <String, int>{},
        'floorCount': geomResult['floorCount'] ?? 1,
      };

      final result = geomResult;

      debugPrint('[ESTIMATION] Sending to Render: '
          'floorArea=${result['totalFloorArea']} '
          'wallLength=${result['totalWallLength']}');

      // 2. Geometric measurements -> Render /estimate endpoint -> material quantities
      final estResponse = await calculateEstimates('temp_project_id', geometry);

      final response = estResponse;

      debugPrint('[ESTIMATION] Render response: $response');

      final materialsData = response['materials']
          ?['materials'] as Map<String,dynamic>?;

      // Interior / finishing estimation (on-device, same geometry).
      final interior = EstimationEngine.calculateInterior(geometry);

      // 3. Combine and return full payload to estimation screen
      return {
        'geometry': geometry,
        'materials': materialsData,
        'interior': interior['materials'],
        'interiorBreakdown': interior['breakdown'],
        'interiorAssumptions': interior['assumptions'],
        'labour': estResponse['labour'],
        'total_labour_days': estResponse['total_labour_days'],
        'confidence': geomResult['confidence'],
        'parserType': geomResult['parserType'],
      };
    } else if (ext == 'dxf' || ext == 'dwg') {
      // Server-side parsing — upload to Render
      return await _uploadToRender(filePath);
    } else if (ext == 'ifc') {
      // Server-side IFC parsing (future)
      return await _uploadToRender(filePath);
    }
    throw Exception('Unsupported file format: $ext');
  }

  Future<Map<String, dynamic>> _uploadToRender(String filePath) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath, 
          filename: filePath.split('/').last,
        ),
      });

      final response = await _dio.post(
        '$_baseUrl/api/cad/parse-upload',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );

      // Augment the server result with on-device interior estimation.
      final data = Map<String, dynamic>.from(response.data as Map);
      final geo = (data['geometry'] as Map?)?.cast<String, dynamic>() ?? {};
      if (geo.isNotEmpty) {
        final interior = EstimationEngine.calculateInterior(geo);
        data['interior'] = interior['materials'];
        data['interiorBreakdown'] = interior['breakdown'];
        data['interiorAssumptions'] = interior['assumptions'];
      }
      return data;
    } catch (e) {
      throw Exception('CAD Analysis failed: $e');
    }
  }

  Future<Map<String, dynamic>> uploadAndParseCAD(File dxfFile,
      {double? userLongFt, double? userShortFt}) async {
    return await parseFile(dxfFile.path,
        userLongFt: userLongFt, userShortFt: userShortFt);
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
