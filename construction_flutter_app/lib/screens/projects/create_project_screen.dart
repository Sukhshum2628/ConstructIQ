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
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

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

  // Which estimation to show/save: 'structural', 'interior', or 'both'.
  String _estimationType = 'both';

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
      final extension = selectedPath.toLowerCase();
      if (!extension.endsWith('.dxf') && !extension.endsWith('.pdf')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a valid .dxf or .pdf file', style: TextStyle(color: Colors.white)),
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
        var analysis = await ref.read(estimationServiceProvider).uploadAndParseCAD(_selectedCadFile!);

        // Drawing carries no scale and no readable overall dimensions — ask the
        // user for the building's overall size, then re-run with those values.
        if (analysis['parserType'] == 'ml_pdf_needs_scale') {
          if (!mounted) return;
          setState(() => _isAnalyzing = false);
          final dims = await _promptForDimensions();
          if (dims == null) {
            setState(() => _cadParsed = false);
            return;
          }
          setState(() => _isAnalyzing = true);
          analysis = await ref.read(estimationServiceProvider).uploadAndParseCAD(
              _selectedCadFile!, userLongFt: dims[0], userShortFt: dims[1]);

          // Still couldn't size it (e.g. no rooms detected) — stop here with a
          // clear message instead of trying to render an incomplete result.
          if (analysis['parserType'] == 'ml_pdf_needs_scale' ||
              analysis['parserType'] == 'ml_pdf_failed') {
            if (!mounted) return;
            setState(() => _cadParsed = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not size this drawing from the dimensions provided. Please check the plan or try a DXF.'),
              backgroundColor: Colors.orange,
            ));
            return;
          }
        }

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

  // Asks the user for the building's overall dimensions when a PDF plan has no
  // embedded scale and no readable overall dimensions. Returns [long, short] in
  // feet, or null if cancelled.
  Future<List<double>?> _promptForDimensions() {
    return showDialog<List<double>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DimensionInputDialog(),
    );
  }

  void _getCurrentLocation() async {
    setState(() => _isLoading = true);
    debugPrint('[GPS] Starting location fetch...');
    try {
      // 1. Check Service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled. Please enable GPS.';
      }

      // 2. Check Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied';
      }

      Position? position;

      // 3. Try Last Known Position (Instant)
      debugPrint('[GPS] Checking last known position...');
      position = await Geolocator.getLastKnownPosition();
      
      if (position != null) {
        debugPrint('[GPS] Using last known position: ${position.latitude}, ${position.longitude}');
      } else {
        // 4. Get Fresh Position with 30s Timeout
        // NOTE: We use LocationAccuracy.low (Network/WiFi) for speed and reliability indoors
        debugPrint('[GPS] Requesting fresh position (Low Accuracy - Network/WiFi)...');
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low, 
            timeLimit: const Duration(seconds: 30),
            forceLocationManager: true, 
          ),
        );
        debugPrint('[GPS] Fresh position captured: ${position.latitude}, ${position.longitude}');
      }
      
      // 5. Geocoding with Fallback
      try {
        debugPrint('[GPS] Attempting reverse geocoding...');
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude
        ).timeout(const Duration(seconds: 10));

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final locationStr = "${place.locality ?? 'Unknown'}, ${place.administrativeArea ?? 'Unknown'}";
          setState(() {
            _locationController.text = locationStr;
          });
          debugPrint('[GPS] Geocoding success: $locationStr');
        } else {
          throw 'No address found';
        }
      } catch (geoError) {
        debugPrint('[GPS] Geocoding failed: $geoError. Using raw coordinates.');
        setState(() {
          _locationController.text = "${position!.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location captured'),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('[GPS] Final Error: $e');
      if (mounted) {
        String userFriendlyError = e.toString();
        if (userFriendlyError.contains('TimeoutException')) {
          userFriendlyError = "GPS signal weak. Try moving near a window or enter location manually.";
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(userFriendlyError),
          backgroundColor: Colors.orange.shade900,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

      // Planned budget = (selected) structural ×2.5 (material + contractor) +
      // interior ×1.4 (material + finishing labour).
      double structCost = 0.0;
      final mats = (_analysisResult?['materials'] ?? {}) as Map<String, dynamic>;
      mats.forEach((name, data) {
        if (name == 'metadata') return;
        final qty = ((data?['quantity'] ?? 0) as num).toDouble();
        structCost += MaterialRates.calculateEstimatedCost(name, qty);
      });
      double interiorCost = 0.0;
      final interiorMats = (_analysisResult?['interior'] ?? {}) as Map<String, dynamic>;
      interiorMats.forEach((name, data) {
        final qty = ((data?['quantity'] ?? 0) as num).toDouble();
        interiorCost += MaterialRates.interiorCost(name, qty);
      });
      double calculatedBudget = 0.0;
      if (_estimationType != 'interior') calculatedBudget += structCost * 2.5;
      if (_estimationType != 'structural') calculatedBudget += interiorCost * 1.4;

      final duration = int.tryParse(_durationController.text) ?? 90;
      final String ownerCode = 'CQ-OWN-${const Uuid().v4().substring(0, 4).toUpperCase()}';

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
        ownerUserId: null, // Initially null, will be set when the Owner registers using the ownerCode
        ownerCode: ownerCode,
        durationDays: duration,
        totalWallLength: (_analysisResult?['geometry']?['totalWallLength'] as num?)?.toDouble() ?? 0.0,
        totalFloorArea: (_analysisResult?['geometry']?['totalFloorArea'] as num?)?.toDouble() ?? 0.0,
      );

      await ref.read(projectServiceProvider).createProject(project);
      
      // Save the CAD upload estimate
      final geometryMap = (_analysisResult?['geometry'] ?? {}) as Map;
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
        estimatedMaterials: Map<String, Map<String, dynamic>>.from(_analysisResult?['materials'] ?? {}),
        interiorMaterials: _estimationType != 'structural'
            ? Map<String, dynamic>.from(_analysisResult?['interior'] ?? {})
            : null,
        estimationType: _estimationType,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _buildField('Location', _locationController, 'GPS Coordinates or Address')),
                  const SizedBox(width: 8),
                  Container(
                    margin: const EdgeInsets.only(bottom: 0),
                    height: 52,
                    child: IconButton(
                      onPressed: _getCurrentLocation,
                      icon: const Icon(Icons.my_location, color: DFColors.primary),
                      tooltip: 'Get GPS Location',
                      style: IconButton.styleFrom(
                        backgroundColor: DFColors.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DFSpacing.md),
              _buildField('Sector', _typeController, 'Residential'),
              const SizedBox(height: DFSpacing.md),
              _buildField('Execution Duration (Days)', _durationController, '90', isNumber: true),
              const SizedBox(height: DFSpacing.xl),
              const SizedBox(height: DFSpacing.md),

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
        color: DFColors.primary.withValues(alpha: 0.5),
        borderType: BorderType.RRect,
        radius: const Radius.circular(12),
        dashPattern: const [6, 3],
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: DFColors.primary.withValues(alpha: 0.05),
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
                _selectedCadFile == null ? 'Tap to upload floor plan (.dxf or .pdf)' : _selectedCadFile!.path.split('/').last,
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
    final mat = (_analysisResult?['materials'] as Map?) ?? const {};
    final interior = _analysisResult?['interior'] as Map?;
    final geo = _analysisResult?['geometry'] as Map?;
    final bool renovation = geo?['projectType'] == 'renovation';
    final bool showStructural = _estimationType != 'interior';
    final bool showInterior =
        _estimationType != 'structural' && interior != null && interior.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: DFSpacing.xl),
      padding: const EdgeInsets.all(DFSpacing.md),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outline.withValues(alpha: 0.2)),
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
          if (!renovation) _buildEstimationTypeSelector(),
          const Divider(),
          Opacity(
            opacity: _cadIsPlausible ? 1.0 : 0.45,
            child: Column(
              children: [
                _analysisRow('Floor Area', '${geo?['totalFloorArea'] ?? 0.0} m²'),
                if (renovation) ...[
                  _analysisRow('Wall Tiles (Renovation)', '${mat['wall_tiles']?['quantity'] ?? 0} m²'),
                  _analysisRow('Floor Tiles (Renovation)', '${mat['floor_tiles']?['quantity'] ?? 0} m²'),
                  _analysisRow('Paint Area', '${mat['paint']?['quantity'] ?? 0} m²'),
                ] else ...[
                  if (showStructural) ..._structuralRows(mat),
                  if (showInterior) ..._interiorRows(interior),
                ],
              ],
            ),
          ),
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

  Widget _buildEstimationTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 'structural', label: Text('Structural', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'interior', label: Text('Interior', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'both', label: Text('Both', style: TextStyle(fontSize: 12))),
          ],
          selected: {_estimationType},
          onSelectionChanged: (s) => setState(() => _estimationType = s.first),
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(t,
              style: DFTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: DFColors.primary,
                  letterSpacing: 1.0)),
        ),
      );

  List<Widget> _structuralRows(Map mat) => [
        _sectionLabel('STRUCTURAL'),
        _analysisRow('Estimated Bricks', '${mat['bricks']?['quantity'] ?? 0} nos'),
        _analysisRow('Cement Needed', '${mat['cement']?['quantity'] ?? 0} bags'),
        _analysisRow('Steel Req.', '${mat['steel']?['quantity'] ?? 0} kg'),
        _analysisRow('Sand Estimate',
            '${MaterialRates.getQuantityInRateUnit('sand', ((mat['sand']?['quantity'] ?? 0) as num).toDouble()).toStringAsFixed(1)} cu.ft'),
        _analysisRow('Aggregate Est.',
            '${MaterialRates.getQuantityInRateUnit('aggregate', ((mat['aggregate']?['quantity'] ?? 0) as num).toDouble()).toStringAsFixed(1)} cu.ft'),
      ];

  List<Widget> _interiorRows(Map interior) {
    final rows = <Widget>[_sectionLabel('INTERIOR / FINISHES')];
    double total = 0;
    interior.forEach((key, data) {
      final qty = ((data?['quantity'] ?? 0) as num).toDouble();
      final unit = (data?['unit'] ?? '').toString();
      final cost = MaterialRates.interiorCost(key.toString(), qty);
      total += cost;
      final qtyStr =
          qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(1);
      rows.add(_analysisRow(MaterialRates.interiorLabel(key.toString()),
          '$qtyStr $unit  ·  ₹${_inr(cost)}'));
    });
    rows.add(_analysisRow('Interior Total', '≈ ₹${_inr(total)}'));
    return rows;
  }

  // Plain thousands-grouped integer rupees.
  String _inr(num v) {
    final s = v.round().abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
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

// Dialog that collects the building's overall plot size (feet) for plans that
// have no embedded scale and no readable dimensions. Owns its controllers so
// their lifecycle is tied to the dialog (avoids "used after disposed" errors).
class _DimensionInputDialog extends StatefulWidget {
  const _DimensionInputDialog();

  @override
  State<_DimensionInputDialog> createState() => _DimensionInputDialogState();
}

class _DimensionInputDialogState extends State<_DimensionInputDialog> {
  final _longCtrl = TextEditingController();
  final _shortCtrl = TextEditingController();

  @override
  void dispose() {
    _longCtrl.dispose();
    _shortCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final l = double.tryParse(_longCtrl.text.trim());
    final s = double.tryParse(_shortCtrl.text.trim());
    if (l != null && s != null && l > 0 && s > 0) {
      Navigator.pop(context, [l, s]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter building size'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This drawing has no scale or overall dimensions, so the area '
              "can't be measured automatically. Enter the building's overall "
              'plot size in feet.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _longCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Longer side (ft)',
                hintText: 'e.g. 50',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _shortCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Shorter side (ft)',
                hintText: 'e.g. 30',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Estimate'),
        ),
      ],
    );
  }
}
