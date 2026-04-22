import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/project_model.dart';
import '../../models/estimate_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../utils/design_tokens.dart';
import '../../utils/material_rates.dart';
import '../../widgets/df_button.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  ConsumerState<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _typeController = TextEditingController();
  final _durationController = TextEditingController(text: "90");
  String? _selectedOwnerId;

  File? _selectedCadFile;
  Map<String, dynamic>? _analysisResult;
  bool _isAnalyzing = false;

  // CAD Validation State
  bool _cadParsed = false;
  bool _cadIsPlausible = true;
  String? _cadValidationWarning;
  String? _cadSuggestedAction;

  void _pickCADFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      final selectedPath = result.files.single.path!;
      if (!selectedPath.toLowerCase().endsWith('.dxf')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a valid .dxf file', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ));
        return;
      }

      setState(() {
        _selectedCadFile = File(selectedPath);
        _isAnalyzing = true;
        _analysisResult = null; // Clear old analysis to avoid UI flickering/confusion
        _cadParsed = false;
        _cadIsPlausible = true;
        _cadValidationWarning = null;
        _cadSuggestedAction = null;
      });

      try {
        final analysis = await ref.read(estimationServiceProvider).uploadAndParseCAD(_selectedCadFile!);
        
        if (analysis['error'] == 'PDF_CONVERTED_DXF') {
          setState(() {
            _analysisResult = analysis;
            _cadParsed = true;
            _cadIsPlausible = false;
            _cadValidationWarning = analysis['message'];
            _cadSuggestedAction = analysis['validation']['suggestedAction'];
          });
          return;
        }

        final validationData = analysis['validation'] as Map<String, dynamic>?;
        final bool isPlausible = validationData?['isPlausible'] as bool? ?? true;
        final String? validationWarning = validationData?['reason'] as String? ?? validationData?['warning'] as String?;
        final String? suggestedAction = validationData?['suggestedAction'] as String?;

        setState(() {
          _analysisResult = analysis;
          _cadParsed = true;
          _cadIsPlausible = isPlausible;
          _cadValidationWarning = validationWarning;
          _cadSuggestedAction = suggestedAction;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CAD Analysis failed: $e')));
      } finally {
        setState(() => _isAnalyzing = false);
      }
    }
  }



  void _generateAndShareReport() async {
    if (_analysisResult == null) return;
    setState(() => _isLoading = true);
    try {
      final bytes = await ref.read(estimationServiceProvider).generateEstimationReport(
        _nameController.text.isEmpty ? "Project Analysis" : _nameController.text,
        _analysisResult!,
      );

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/estimation_report.pdf');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Estimation Report for ${_nameController.text}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_analysisResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload and analyze a CAD file first.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) return;

      // Calculate planned budget from CAD analysis (Material Cost + Contractor Share)
      double matCost = 0.0;
      final mats = _analysisResult!['materials'] as Map<String, dynamic>;
      mats.forEach((name, data) {
        if (name == 'metadata') return;
        final qty = (data['quantity'] as num).toDouble();
        matCost += MaterialRates.calculateEstimatedCost(name, qty);
      });
      final calculatedBudget = matCost * 2.5; // Material + 1.5x Contractor Share

      final duration = int.tryParse(_durationController.text) ?? 90;
      final project = ProjectModel(
        projectId: const Uuid().v4(),
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        startDate: DateTime.now(),
        expectedEndDate: DateTime.now().add(Duration(days: duration)),
        status: ProjectStatus.active,
        createdBy: user.uid,
        teamMembers: [user.uid],
        plannedBudget: calculatedBudget,
        projectType: _typeController.text.isEmpty ? 'Residential' : _typeController.text.trim(),
        cadFileUrl: 'uploaded-via-stream',
        estimationStatus: EstimationStatus.completed,
        createdAt: DateTime.now(),
        ownerUserId: _selectedOwnerId,
        durationDays: duration,
        totalWallLength: (_analysisResult!['geometry']['totalWallLength'] as num?)?.toDouble() ?? 0.0,
        totalFloorArea: (_analysisResult!['geometry']['totalFloorArea'] as num?)?.toDouble() ?? 0.0,
      );

      await ref.read(projectServiceProvider).createProject(project);
      
      // Save the CAD upload estimate
      final geometryMap = _analysisResult!['geometry'] as Map;
      final estimate = EstimateModel(
        estimateId: const Uuid().v4(),
        generatedAt: DateTime.now(),
        cadFileName: _selectedCadFile?.path.split('/').last ?? 'uploaded_drawing.dxf',
        geometryData: Map<String, double>.fromEntries(
          geometryMap.entries.map((e) {
             if (e.value is num) return MapEntry(e.key.toString(), (e.value as num).toDouble());
             return null;
          }).whereType<MapEntry<String, double>>()
        ),
        estimatedMaterials: Map<String, Map<String, dynamic>>.from(_analysisResult!['materials']),
        confidence: EstimationConfidence.high,
      );
      
      await FirebaseFirestore.instance
          .collection('projects')
          .doc(project.projectId)
          .collection('estimates')
          .doc(estimate.estimateId)
          .set(estimate.toJson());

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.red.shade900,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('New Project Initiation', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        backgroundColor: DFColors.background,
        elevation: 0,
        leading: const BackButton(color: DFColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DFSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BASIC MISSION INTEL', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: DFColors.primary)),
              const SizedBox(height: DFSpacing.md),
              _buildField('Project Name', _nameController, 'Neo-Matrix Residency'),
              const SizedBox(height: DFSpacing.md),
              _buildField('Location', _locationController, 'GPS Coordinates or Address'),
              const SizedBox(height: DFSpacing.md),
              _buildField('Sector', _typeController, 'Residential'),
              const SizedBox(height: DFSpacing.md),
              _buildField('Execution Duration (Days)', _durationController, '90', isNumber: true),
              const SizedBox(height: DFSpacing.xl),
              
              Text('PROJECT OWNER', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: DFSpacing.sm),
              _buildOwnerDropdown(),
              const SizedBox(height: DFSpacing.xl),

              Text('STRUCTURAL BLUEPRINT (DXF)', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: DFColors.primary)),
              const SizedBox(height: DFSpacing.md),
              _buildCADUploadZone(),
              
              if (_analysisResult != null) _buildAnalysisSummary(),
              
              const SizedBox(height: DFSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: DFButton(
                  label: _cadIsPlausible
                      ? 'Activate Project'.toUpperCase()
                      : 'FIX CAD FILE TO CONTINUE',
                  isLoading: _isLoading,
                  onPressed: (_cadParsed && _cadIsPlausible) ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCADUploadZone() {
    return GestureDetector(
      onTap: _pickCADFile,
      child: DottedBorder(
        color: DFColors.primary.withOpacity(0.5),
        borderType: BorderType.RRect,
        radius: const Radius.circular(12),
        dashPattern: const [6, 3],
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: DFColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _selectedCadFile == null ? Icons.upload_file : Icons.check_circle,
                size: 32,
                color: _selectedCadFile == null ? DFColors.primary : DFColors.success,
              ),
              const SizedBox(height: DFSpacing.xs),
              Text(
                _selectedCadFile == null ? 'Tap to upload floor plan (.dxf)' : _selectedCadFile!.path.split('/').last,
                style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_isAnalyzing) ...[
                const SizedBox(height: 8),
                const SizedBox(width: 100, child: LinearProgressIndicator(minHeight: 2)),
                const SizedBox(height: 4),
                Text('AI ANALYZING GEOMETRY...', style: DFTextStyles.caption.copyWith(fontSize: 10)),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildAnalysisSummary() {
    final mat = _analysisResult!['materials'];
    final geo = _analysisResult!['geometry'];
    final validation = _analysisResult!['validation'] ?? {'isPlausible': true};

    return Container(
      margin: const EdgeInsets.only(top: DFSpacing.xl),
      padding: const EdgeInsets.all(DFSpacing.md),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ESTIMATION PREVIEW', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
              IconButton(
                icon: const Icon(Icons.share, size: 20, color: DFColors.primary),
                onPressed: _generateAndShareReport,
              )
            ],
          ),
          const Divider(),

          const Divider(),

          Opacity(
            opacity: _cadIsPlausible ? 1.0 : 0.45,
            child: Column(
              children: [
                _analysisRow('Floor Area', '${geo['totalFloorArea']} m²'),
                if (geo['projectType'] == 'renovation') ...[
                  _analysisRow('Wall Tiles (Renovation)', '${mat['wall_tiles']?['quantity'] ?? 0} m²'),
                  _analysisRow('Floor Tiles (Renovation)', '${mat['floor_tiles']?['quantity'] ?? 0} m²'),
                  _analysisRow('Paint Area', '${mat['paint']?['quantity'] ?? 0} m²'),
                ] else ...[
                  _analysisRow('Estimated Bricks', '${mat['bricks']?['quantity'] ?? 0} nos'),
                  _analysisRow('Cement Needed', '${mat['cement']?['quantity'] ?? 0} bags'),
                  _analysisRow('Steel Req.', '${mat['steel']?['quantity'] ?? 0} kg'),
                  _analysisRow('Sand Estimate', '${MaterialRates.getQuantityInRateUnit('sand', (mat['sand']?['quantity'] ?? 0).toDouble()).toStringAsFixed(1)} cu.ft'),
                  _analysisRow('Aggregate Est.', '${MaterialRates.getQuantityInRateUnit('aggregate', (mat['aggregate']?['quantity'] ?? 0).toDouble()).toStringAsFixed(1)} cu.ft'),
                ],
              ],
            ),
          ),
          const SizedBox(height: DFSpacing.sm),
          
          const SizedBox(height: DFSpacing.sm),
        ],
      ),
    );
  }

  Widget _analysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: DFTextStyles.caption),
          Text(value, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: DFSpacing.xs),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          style: DFTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: DFTextStyles.caption.copyWith(color: DFColors.textCaption),
            filled: true,
            fillColor: DFColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(DFSpacing.md),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerDropdown() {
    final ownersAsync = ref.watch(allOwnersProvider);
    return ownersAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error loading owners', style: DFTextStyles.caption.copyWith(color: DFColors.critical)),
      data: (owners) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: DFSpacing.md),
          decoration: BoxDecoration(color: DFColors.surface, borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedOwnerId,
              isExpanded: true,
              hint: Text('Assign Client / Owner', style: DFTextStyles.caption),
              items: owners.map((o) => DropdownMenuItem(value: o.uid, child: Text(o.name, style: DFTextStyles.body))).toList(),
              onChanged: (val) => setState(() => _selectedOwnerId = val),
            ),
          ),
        );
      },
    );
  }
}
