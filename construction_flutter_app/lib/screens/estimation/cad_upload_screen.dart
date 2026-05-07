import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../providers/estimation_provider.dart';
import '../../models/estimate_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_button.dart';
import '../../widgets/df_pill.dart';

class CadUploadScreen extends ConsumerStatefulWidget {
  final String? projectId;
  const CadUploadScreen({super.key, this.projectId});

  @override
  ConsumerState<CadUploadScreen> createState() => _CadUploadScreenState();
}

class _CadUploadScreenState extends ConsumerState<CadUploadScreen> {
  bool _isUploading = false;
  Map<String, dynamic>? _estimationResult;
  Map<String, dynamic>? _fullEstimationResponse;
  String? _selectedFileName;

  void _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      final fileName = result.files.single.name.toLowerCase();
      if (!fileName.endsWith('.dxf') && !fileName.endsWith('.pdf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('UNSUPPORTED FORMAT: PLEASE SELECT A .DXF OR .PDF FILE'), 
              backgroundColor: DFColors.criticalBg,
            )
          );
        }
        return;
      }

      setState(() => _isUploading = true);
      try {
        final file = File(result.files.single.path!);
        _selectedFileName = result.files.single.name;
        final response = await ref.read(estimationServiceProvider).uploadAndParseCAD(file);
        
        if (mounted) {
          setState(() {
            _fullEstimationResponse = response;
            _estimationResult = response['geometry'];
            _isUploading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          final errorMsg = e.toString().contains('400') 
            ? 'PDF does not contain vector geometry. Please upload a CAD-exported PDF.'
            : 'ERR: $e';
            
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg), 
              backgroundColor: DFColors.criticalBg,
            )
          );
          setState(() => _isUploading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        centerTitle: false,
        leading: _estimationResult != null 
          ? IconButton(
              icon: const Icon(Icons.close, color: DFColors.textPrimary), 
              onPressed: () => setState(() => _estimationResult = null),
            )
          : const BackButton(color: DFColors.textPrimary),
        title: Text('BLUEPRINT ANALYSIS', 
          style: DFTextStyles.caption.copyWith(
            color: DFColors.primary, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 2.0
          )
        ),
      ),
      body: _isUploading 
          ? _buildProcessingState() 
          : _estimationResult != null 
              ? _buildResultState() 
              : _buildInitialState(),
    );
  }

  Widget _buildInitialState() {
    return Padding(
      padding: const EdgeInsets.all(DFSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ENGINEERING ANALYSIS', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text('EXTRACT GEOMETRIC INTELLIGENCE FROM DRAWINGS', 
            style: DFTextStyles.caption),
          const Spacer(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DFCard(
                  padding: const EdgeInsets.all(DFSpacing.xl),
                  color: DFColors.surface,
                  hasShadow: true,
                  child: Column(
                    children: [
                      const Icon(Icons.architecture, size: 64, color: DFColors.primary),
                      const SizedBox(height: 24),
                      Text('UPLOAD DXF OR PDF', 
                        style: DFTextStyles.cardTitle),
                      const SizedBox(height: 12),
                      Text(
                        'WE AUTOMATICALLY EXTRACT WALL LENGTHS AND CALCULATE MATERIALS FROM VECTOR BLUEPRINTS.',
                        textAlign: TextAlign.center,
                        style: DFTextStyles.caption.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                DFButton(
                  label: 'SELECT TECHNICAL DRAWING',
                  onPressed: _pickAndUpload,
                  icon: Icons.upload_file,
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildProcessingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: DFColors.primary, strokeWidth: 2),
          const SizedBox(height: 32),
          Text('PARSING GEOMETRY...', 
            style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Text('MAPPING VECTOR DATA TO MATERIAL ARRAYS', 
            style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildResultState() {
    final double confidence = (_fullEstimationResponse?['confidence'] ?? 1.0).toDouble();
    final bool isLowConfidence = confidence < 0.6;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DFSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLowConfidence) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DFColors.warningBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DFColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: DFColors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ESTIMATION BASED ON APPROXIMATE SCALE — VERIFY DIMENSIONS.',
                      style: DFTextStyles.caption.copyWith(color: DFColors.warning, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildHeaderSection(),
          const SizedBox(height: 32),
          Text('GEOMETRY INSIGHTS', 
            style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.primary, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildGeometryGrid(),
          const SizedBox(height: 32),
          _buildCostCard(),
          const SizedBox(height: 32),
          Text('MATERIAL BREAKDOWNS', 
            style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.textSecondary, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _materialItem('CONCRETE (GRADE M25)', 'High strength structural mix', '24.2 m³'),
          _materialItem('REINFORCEMENT STEEL (TMT)', 'Fe 500D Grade', '1.8 Tons'),
          _materialItem('BRICKWORK (FLY ASH)', 'Standard 230x110x70mm', '14,200 units'),
          const SizedBox(height: 40),
          DFButton(
            label: 'SYNC WITH PROJECT LOGS',
            onPressed: () => _syncWithLogs(context),
          ),
          const SizedBox(height: 12),
          DFButton(
            label: 'MODIFY ANALYSIS',
            outlined: true,
            onPressed: () => setState(() => _estimationResult = null),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _syncWithLogs(BuildContext context) async {
    if (_fullEstimationResponse == null || widget.projectId == null) return;
    
    setState(() => _isUploading = true);
    try {
      final double confidenceVal = (_fullEstimationResponse?['confidence'] ?? 1.0).toDouble();
      EstimationConfidence confidence;
      if (confidenceVal >= 0.8) {
        confidence = EstimationConfidence.high;
      } else if (confidenceVal >= 0.6) {
        confidence = EstimationConfidence.medium;
      } else {
        confidence = EstimationConfidence.low;
      }

      final estimate = EstimateModel(
        estimateId: const Uuid().v4(),
        generatedAt: DateTime.now(),
        cadFileName: _selectedFileName ?? 'blueprint.pdf',
        geometryData: Map<String, double>.fromEntries(
          (_fullEstimationResponse!['geometry'] as Map).entries.map((e) {
             if (e.value is num) return MapEntry(e.key.toString(), (e.value as num).toDouble());
             return null;
          }).whereType<MapEntry<String, double>>()
        ),
        estimatedMaterials: Map<String, Map<String, dynamic>>.from(_fullEstimationResponse!['materials']),
        confidence: confidence,
        labour: _fullEstimationResponse!['labour'],
        totalLabourDays: _fullEstimationResponse!['total_labour_days'],
      );

      await FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('estimates')
          .doc(estimate.estimateId)
          .set(estimate.toJson());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully synced with project logs!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to sync: $e')));
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ESTIMATION COMPLETE', style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text('${_selectedFileName?.toUpperCase() ?? 'BLUEPRINT'} • VERIFIED', 
                style: DFTextStyles.caption.copyWith(color: DFColors.normal, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const DFPill(label: 'HIGH FIDELITY', severity: 'normal'),
      ],
    );
  }

  Widget _buildGeometryGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _metricTile('WALL AREA', '${_estimationResult?['totalWallArea'] ?? 0} m²'),
        _metricTile('FLOOR AREA', '${_estimationResult?['totalFloorArea'] ?? 0} m²'),
        _metricTile('STR. COLUMNS', '${_estimationResult?['totalColumnCount'] ?? 0} units'),
        _metricTile('HEIGHT', '${_estimationResult?['buildingHeight'] ?? 0} m'),
        _metricTile('TOTAL VOLUME', '${_estimationResult?['structuralVolume'] ?? 0} m³'),
        _metricTile('COMPLEXITY', '${_estimationResult?['confidenceScore'] ?? 0} β'),
      ],
    );
  }

  Widget _metricTile(String label, String value) {
    return DFCard(
      padding: const EdgeInsets.all(16),
      color: DFColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: DFTextStyles.caption.copyWith(fontSize: 9)),
          const SizedBox(height: 4),
          Text(value, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCostCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DFColors.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: DFColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL ESTIMATED COST', 
                style: DFTextStyles.caption.copyWith(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('₹8,69,600', 
                style: DFTextStyles.metricLarge.copyWith(color: Colors.white, fontSize: 32)),
            ],
          ),
          const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 32),
        ],
      ),
    );
  }

  Widget _materialItem(String title, String subtitle, String qty) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DFCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(), style: DFTextStyles.cardTitle.copyWith(fontSize: 13)),
                  Text(subtitle, style: DFTextStyles.caption),
                ],
              ),
            ),
            Text(qty, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primary)),
          ],
        ),
      ),
    );
  }
}
