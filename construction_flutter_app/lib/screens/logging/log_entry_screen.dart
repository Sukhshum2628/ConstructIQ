import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../models/resource_log_model.dart';
import '../../models/delay_record_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../providers/weather_provider.dart';
import '../../providers/delay_provider.dart';
import '../../services/weather_service.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../models/project_model.dart';
import '../../models/weather_model.dart';
import '../../providers/project_provider.dart';
import '../../providers/estimation_provider.dart';

class EquipmentController {
  final TextEditingController name;
  final TextEditingController used;
  final TextEditingController idle;

  EquipmentController({String nameText = ''})
      : name = TextEditingController(text: nameText),
        used = TextEditingController(text: '0.0'),
        idle = TextEditingController(text: '0.0');

  void dispose() {
    name.dispose();
    used.dispose();
    idle.dispose();
  }
}

class LogEntryScreen extends ConsumerStatefulWidget {
  final String? projectId;
  const LogEntryScreen({super.key, this.projectId});

  @override
  ConsumerState<LogEntryScreen> createState() => _LogEntryScreenState();
}

class _LogEntryScreenState extends ConsumerState<LogEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Materials
  final _cementController = TextEditingController(text: "42");
  final _rebarController = TextEditingController(text: "150");
  final _admixtureController = TextEditingController(text: "14");
  final _sandController = TextEditingController(text: "4.2");
  
  // Dynamic Equipments
  final List<EquipmentController> _equipmentControllers = [];
  
  final _notesController = TextEditingController();
  
  String _selectedWeather = 'Sunny';
  bool _isLoading = false;
  bool _isWeatherLocked = false;   // True when adverse weather selected
  bool _showMaterialDelay = false; // Material delay toggle
  XFile? _image;
  Map<String, double>? _location;
  WeatherData? _liveWeather;       // Live weather from API

  // Material delay fields
  final _delayMaterialNameController = TextEditingController();
  DateTime? _expectedDeliveryDate;
  DateTime? _actualDeliveryDate;


  @override
  void initState() {
    super.initState();
    // Start with one default row
    _addEquipmentRow('Excavator E-04');
  }

  void _addEquipmentRow([String name = '']) {
    final controller = EquipmentController(nameText: name);
    controller.used.addListener(_rebuild);
    controller.idle.addListener(_rebuild);
    setState(() {
      _equipmentControllers.add(controller);
    });
  }

  void _removeEquipmentRow(int index) {
    if (_equipmentControllers.length <= 1) return;
    setState(() {
      final controller = _equipmentControllers.removeAt(index);
      controller.used.removeListener(_rebuild);
      controller.idle.removeListener(_rebuild);
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (var ctrl in _equipmentControllers) {
      ctrl.used.removeListener(_rebuild);
      ctrl.idle.removeListener(_rebuild);
      ctrl.dispose();
    }
    
    _cementController.dispose();
    _rebarController.dispose();
    _admixtureController.dispose();
    _sandController.dispose();
    _notesController.dispose();
    _delayMaterialNameController.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      setState(() => _image = image);
    }
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }

  void _submit() async {
    if (widget.projectId == null) return;
    
    final project = ref.read(projectByIdProvider(widget.projectId!)).value;
    if (project?.status == ProjectStatus.closed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot submit log: Project is closed.'), backgroundColor: DFColors.critical),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    
    await Future.delayed(const Duration(milliseconds: 1000));
    
    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) return;

      // Capture Geotag
      final position = await _determinePosition();
      if (position != null) {
        _location = {'lat': position.latitude, 'lng': position.longitude};
      }

      final logId = const Uuid().v4();

      // ── Weather Delay Verification ──
      if (_isWeatherLocked) {
        final weatherService = ref.read(weatherServiceProvider);
        String? weatherProof;
        DelayStatus delayStatus = DelayStatus.verified;

        // Try to verify against API
        if (_location != null) {
          final apiWeather = await weatherService.getCurrentWeather(_location!['lat']!, _location!['lng']!);
          weatherProof = await weatherService.getWeatherProofSnapshot(_location!['lat']!, _location!['lng']!);

          if (apiWeather != null && !weatherService.verifyUserClaim(_selectedWeather, apiWeather)) {
            // Mismatch! Require photo override
            if (mounted) {
              final shouldOverride = await _showWeatherMismatchDialog(apiWeather);
              if (!shouldOverride) {
                setState(() => _isLoading = false);
                return;
              }
              if (_image == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A site photo is mandatory for weather override.'), backgroundColor: DFColors.critical),
                );
                setState(() => _isLoading = false);
                return;
              }
              delayStatus = DelayStatus.overridden;
            }
          }
        }

        // Create delay record
        final delayRecord = DelayRecord(
          id: const Uuid().v4(),
          projectId: widget.projectId!,
          type: DelayType.weather,
          reason: '$_selectedWeather conditions — Site work suspended',
          date: DateTime.now(),
          daysLost: 1,
          status: delayStatus,
          weatherApiProof: weatherProof,
          recordedBy: user.uid,
          createdAt: DateTime.now(),
          linkedLogId: logId,
        );

        await addDelayRecord(delayRecord);
      }

      // ── Material Delay Record ──
      if (_showMaterialDelay && _expectedDeliveryDate != null) {
        final daysDelayed = _actualDeliveryDate != null
            ? _actualDeliveryDate!.difference(_expectedDeliveryDate!).inDays
            : DateTime.now().difference(_expectedDeliveryDate!).inDays;
        
        if (daysDelayed > 0) {
          final materialDelay = DelayRecord(
            id: const Uuid().v4(),
            projectId: widget.projectId!,
            type: DelayType.materialShortage,
            reason: '${_delayMaterialNameController.text.isEmpty ? "Material" : _delayMaterialNameController.text} delivery delayed by $daysDelayed days',
            date: DateTime.now(),
            daysLost: daysDelayed,
            status: DelayStatus.verified,
            recordedBy: user.uid,
            createdAt: DateTime.now(),
            linkedLogId: logId,
          );

          await addDelayRecord(materialDelay);
        }
      }

      // ── Create the Resource Log ──
      final List<EquipmentEntry> equipmentList = _equipmentControllers.map((c) => EquipmentEntry(
        name: c.name.text.isEmpty ? 'Generic' : c.name.text,
        usedHours: _isWeatherLocked ? 0.0 : (double.tryParse(c.used.text) ?? 0.0),
        idleHours: _isWeatherLocked ? 0.0 : (double.tryParse(c.idle.text) ?? 0.0),
      )).toList();

      final log = ResourceLogModel(
        id: logId,
        projectId: widget.projectId!,
        loggedBy: user.uid,
        date: DateTime.now(),
        location: _location,
        materialUsage: _isWeatherLocked ? {'cement': 0, 'rebar': 0, 'admixture': 0, 'sand': 0} : {
          'cement': double.tryParse(_cementController.text) ?? 0.0,
          'rebar': double.tryParse(_rebarController.text) ?? 0.0,
          'admixture': double.tryParse(_admixtureController.text) ?? 0.0,
          'sand': double.tryParse(_sandController.text) ?? 0.0,
        },
        equipmentList: equipmentList,
        laborHours: 0.0,
        notes: _notesController.text,
        weatherCondition: _selectedWeather,
        isWeatherDelay: _isWeatherLocked,
        createdAt: DateTime.now(),
      );

      await ref.read(resourceLogServiceProvider).addLog(log, photo: _image);
      if (mounted) {
        final message = _isWeatherLocked
            ? 'Weather Delay Recorded — Timeline extended by 1 day'
            : 'Log Evidence Recorded for $projectName';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: DFColors.primaryStitch),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ERR: $e'), backgroundColor: DFColors.critical),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showWeatherMismatchDialog(WeatherData apiWeather) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: DFColors.warning, size: 24),
            SizedBox(width: 8),
            Text('Weather Mismatch'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You selected: $_selectedWeather', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Weather API reports: ${apiWeather.description} (${apiWeather.condition})', 
              style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
            const SizedBox(height: 12),
            Text('To override, a site photo is mandatory as evidence.', 
              style: DFTextStyles.caption),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: DFColors.warning),
            child: const Text('OVERRIDE WITH PHOTO'),
          ),
        ],
      ),
    ) ?? false;
  }

  String get projectName {
     final project = ref.read(projectByIdProvider(widget.projectId!)).value;
     return project?.name ?? widget.projectId!;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projectId == null) return const Scaffold(body: Center(child: Text("Project ID Missing")));

    final projectAsync = ref.watch(projectByIdProvider(widget.projectId!));
    final estimateAsync = ref.watch(latestEstimateProvider(widget.projectId!));

    return projectAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text("Error: $e"))),
      data: (project) {
        if (project == null) return const Scaffold(body: Center(child: Text("Project not found")));

        return estimateAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text("Error loading estimate: $e"))),
          data: (estimate) {
            // Helper to calculate daily estimate
            String getDailyEst(String key, String unit) {
              if (estimate == null || estimate.estimatedMaterials[key] == null) return "Est: ~0 $unit";
              double total = (estimate.estimatedMaterials[key]!['quantity'] as num).toDouble();
              double daily = total / (project.durationDays > 0 ? project.durationDays : 365);
              return "Est: ~${daily.toStringAsFixed(1)} $unit";
            }

            return Scaffold(
              backgroundColor: DFColors.background,
              appBar: _buildAppBar(),
              body: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (project.status == ProjectStatus.closed)
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: DFColors.critical.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_rounded, color: DFColors.critical, size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'PROJECT IS CLOSED. LOGS ARE READ-ONLY.',
                                      style: DFTextStyles.labelSm.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildHeaderInfo(project.name),
                          const SizedBox(height: 32),

                          // ── ADVERSE WEATHER BANNER ──
                          if (_isWeatherLocked) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE65100), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('⚠️ ADVERSE WEATHER DETECTED', 
                                          style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFFE65100))),
                                        const SizedBox(height: 4),
                                        Text('Work logging is disabled. Only observations and site evidence can be recorded.', 
                                          style: DFTextStyles.caption.copyWith(color: const Color(0xFFBF360C), fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          // ── Materials (lockable) ──
                          Stack(
                            children: [
                              Opacity(
                                opacity: _isWeatherLocked ? 0.3 : 1.0,
                                child: IgnorePointer(
                                  ignoring: _isWeatherLocked,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSectionTitle('inventory_2', 'Materials Consumption'),
                                      const SizedBox(height: 16),
                                      _buildMaterialGrid(getDailyEst),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isWeatherLocked)
                                Positioned.fill(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Text('Locked — Adverse Weather', style: DFTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          
                          // ── Equipment (lockable) ──
                          Stack(
                            children: [
                              Opacity(
                                opacity: _isWeatherLocked ? 0.3 : 1.0,
                                child: IgnorePointer(
                                  ignoring: _isWeatherLocked,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSectionTitle('construction', 'Equipment Utilization'),
                                      const SizedBox(height: 16),
                                      _buildEquipmentSection(),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isWeatherLocked)
                                Positioned.fill(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Text('Locked — Adverse Weather', style: DFTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // ── Material Delay Toggle ──
                          _buildMaterialDelaySection(),
                          const SizedBox(height: 32),
                          
                          _buildSectionTitle('edit_note', 'Observations & Issues'),
                          const SizedBox(height: 16),
                          _buildNotesArea(),
                          const SizedBox(height: 32),
                          
                          _buildSectionTitle('camera_alt', 'Site Evidence & Geotag'),
                          const SizedBox(height: 16),
                          _buildEvidenceSection(),
                          const SizedBox(height: 32),
                          
                          _buildSubmitSection(),
                        ],
                      ),
                    ),
                  ),
                  if (_isLoading) _buildShimmerLoader(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: DFColors.surface,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: DFColors.primaryStitch),
        onPressed: () => context.pop(),
      ),
      title: Text('Daily Log', style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
    );
  }

  Widget _buildHeaderInfo(String projectName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Log for $projectName', style: DFTextStyles.screenTitle.copyWith(color: DFColors.primaryStitch, fontSize: 24, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('Phase 2: Structural Reinforcement', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today, size: 16, color: DFColors.primaryStitch),
              const SizedBox(width: 8),
              Text('Oct 24, 2026 (Today)', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 16, color: DFColors.outlineVariant),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildWeatherChip('Sunny', Icons.sunny, 'Sunny'),
            _buildWeatherChip('Cloudy', Icons.cloud, 'Cloudy'),
            _buildWeatherChip('Rainy', Icons.water_drop, 'Rainy'),
            _buildWeatherChip('Stormy', Icons.thunderstorm, 'Stormy'),
            _buildWeatherChip('Foggy', Icons.blur_on, 'Foggy'),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherChip(String label, IconData icon, String value) {
    bool isSelected = _selectedWeather == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedWeather = value;
          // Adverse weather types that lock the log
          _isWeatherLocked = (value == 'Rainy' || value == 'Stormy');
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEA619) : DFColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: isSelected ? Border.all(color: const Color(0xFF684000), width: 1) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF684000) : DFColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: DFTextStyles.body.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF684000) : DFColors.textSecondary,
              fontSize: 12,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialDelaySection() {
    return DFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping, color: DFColors.primaryStitch, size: 20),
              const SizedBox(width: 12),
              Text('Material Delivery Issues', style: DFTextStyles.sectionHeader.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Switch(
                value: _showMaterialDelay,
                onChanged: (val) => setState(() => _showMaterialDelay = val),
                activeColor: DFColors.primaryStitch,
              ),
            ],
          ),
          if (_showMaterialDelay) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _delayMaterialNameController,
              decoration: InputDecoration(
                labelText: 'Material Name (e.g. Cement, Bricks)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) setState(() => _expectedDeliveryDate = date);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: DFColors.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expected Date', style: DFTextStyles.caption),
                          Text(_expectedDeliveryDate == null ? 'Select' : DateFormat('MMM dd').format(_expectedDeliveryDate!),
                            style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) setState(() => _actualDeliveryDate = date);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: DFColors.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Actual Date', style: DFTextStyles.caption),
                          Text(_actualDeliveryDate == null ? 'Pending' : DateFormat('MMM dd').format(_actualDeliveryDate!),
                            style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String iconName, String title) {
    IconData iconData = Icons.inventory_2;
    if (iconName == 'construction') iconData = Icons.construction;
    if (iconName == 'edit_note') iconData = Icons.edit_note;

    return Row(
      children: [
        Icon(iconData, color: DFColors.primaryContainerStitch, size: 20),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryContainerStitch, fontWeight: FontWeight.w600, letterSpacing: 1.0, fontSize: 13)),
      ],
    );
  }

  Widget _buildMaterialGrid(String Function(String, String) dailyEst) {
    return Column(
      children: [
        _buildMaterialCard('Cement (PPC)', dailyEst('cement', 'bags'), 'bags', Icons.conveyor_belt, _cementController),
        const SizedBox(height: 16),
        _buildMaterialCard('Steel Rebar 12mm', dailyEst('steel', 'kg'), 'kg', Icons.architecture, _rebarController),
        const SizedBox(height: 16),
        _buildMaterialCard('Admixture', dailyEst('admixture', 'kg'), 'kg', Icons.water_drop, _admixtureController),
        const SizedBox(height: 16),
        _buildMaterialCard('River Sand', dailyEst('sand', 'm³'), 'm³', Icons.texture, _sandController),
      ],
    );
  }

  Widget _buildMaterialCard(String title, String est, String unit, IconData iconData, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0F191C1E), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(6)),
                child: Icon(iconData, color: DFColors.primaryStitch, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(est, style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontSize: 10)),
                ],
              ),
            ],
          ),
          Container(
            width: 80, height: 40,
            decoration: BoxDecoration(
              color: DFColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: DFTextStyles.screenTitle.copyWith(fontSize: 16),
                    decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4), isDense: true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Text(unit, style: DFTextStyles.labelSm.copyWith(color: DFColors.outlineVariant, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentSection() {
    return Column(
      children: [
        // Quick add common items
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildAddQuickChip('EXCAVATOR', Icons.agriculture),
              const SizedBox(width: 8),
              _buildAddQuickChip('CRANE', Icons.precision_manufacturing),
              const SizedBox(width: 8),
              _buildAddQuickChip('MIXER', Icons.cyclone),
              const SizedBox(width: 8),
              _buildAddQuickChip('TRUCK', Icons.local_shipping),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _equipmentControllers.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0x1Ac2c6d3)),
            itemBuilder: (context, index) => _buildEquipmentRow(index),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _addEquipmentRow(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('ADD OTHER EQUIPMENT'),
          style: TextButton.styleFrom(foregroundColor: DFColors.primaryStitch),
        ),
      ],
    );
  }

  Widget _buildAddQuickChip(String label, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      onPressed: () => _addEquipmentRow(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: DFColors.outlineVariant),
    );
  }

  Widget _buildEquipmentRow(int index) {
    final controller = _equipmentControllers[index];
    
    String calculateRatio() {
      double u = double.tryParse(controller.used.text) ?? 0.0;
      double i = double.tryParse(controller.idle.text) ?? 0.0;
      double total = u + i;
      if (total == 0) return '0%';
      return '${((i / total) * 100).toInt()}%';
    }

    Color getRatioColor(String ratioStr) {
      int ratio = int.tryParse(ratioStr.replaceAll('%', '')) ?? 0;
      if (ratio > 25) return const Color(0xFF850009); // Red for high idle
      return const Color(0xFF059669); // Green for efficient
    }

    final ratio = calculateRatio();
    final ratioColor = getRatioColor(ratio);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.name,
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Equipment Name...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20, color: DFColors.critical),
                onPressed: () => _removeEquipmentRow(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('USED HOURS', style: DFTextStyles.labelSm.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                      child: TextField(
                        controller: controller.used,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 16),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IDLE HOURS', style: DFTextStyles.labelSm.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                      child: TextField(
                        controller: controller.idle,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 16),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('IDLE RATIO', style: DFTextStyles.labelSm.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(ratio, style: DFTextStyles.screenTitle.copyWith(fontSize: 16, color: ratioColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesArea() {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _notesController,
        maxLines: null,
        style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
          hintText: 'Any observations or issues? E.g. Late delivery of sand, labor shortage in Block-A...',
        ),
      ),
    );
  }

  Widget _buildEvidenceSection() {
    return DFCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_image != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_image!.path),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(_image == null ? 'CAPTURE SITE PHOTO' : 'RETAKE PHOTO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DFColors.surfaceContainerLow,
                    foregroundColor: DFColors.primaryStitch,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _location != null ? Icons.location_on : Icons.location_searching,
                size: 14,
                color: _location != null ? DFColors.normal : DFColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                _location != null ? 'GPS Locked' : 'Location will be captured on submit',
                style: DFTextStyles.caption.copyWith(color: _location != null ? DFColors.normal : DFColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: (_isLoading || (ref.read(projectByIdProvider(widget.projectId!)).value?.status == ProjectStatus.closed)) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: DFColors.primaryContainerStitch,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SUBMIT DAILY LOG', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                const SizedBox(width: 12),
                const Icon(Icons.send, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 14, color: DFColors.textSecondary),
            const SizedBox(width: 8),
            Text('Offline? Your log will sync when connected.', style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, color: DFColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerLoader() {
    return Container(
      color: Colors.white.withAlpha(153),
      child: Center(
        child: Container(
          width: 256, height: 8,
          decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(4)),
          child: LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(DFColors.primaryContainerStitch),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

