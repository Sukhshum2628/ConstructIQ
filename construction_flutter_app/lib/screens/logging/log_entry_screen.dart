import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../models/resource_log_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

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
  
  // Equipments (Used/Idle)
  final _excavatorUsedController = TextEditingController(text: "6.5");
  final _excavatorIdleController = TextEditingController(text: "1.5");
  
  final _craneUsedController = TextEditingController(text: "4.0");
  final _craneIdleController = TextEditingController(text: "4.0");
  
  final _mixerUsedController = TextEditingController(text: "8.0");
  final _mixerIdleController = TextEditingController(text: "0.0");
  
  final _notesController = TextEditingController();
  
  String _selectedWeather = 'Sunny';
  bool _isLoading = false;
  XFile? _image;
  Map<String, double>? _location;

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
    setState(() => _isLoading = true);
    
    // Simulate network delay for UI loader
    await Future.delayed(const Duration(milliseconds: 1000));
    
    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) return;

      // Capture Geotag before model creation
      final position = await _determinePosition();
      if (position != null) {
        _location = {'lat': position.latitude, 'lng': position.longitude};
      }

      final log = ResourceLogModel(
        id: const Uuid().v4(),
        projectId: widget.projectId!,
        loggedBy: user.uid,
        date: DateTime.now(),
        location: _location,
        materialUsage: {
          'cement': double.tryParse(_cementController.text) ?? 0.0,
          'rebar': double.tryParse(_rebarController.text) ?? 0.0,
          'admixture': double.tryParse(_admixtureController.text) ?? 0.0,
          'sand': double.tryParse(_sandController.text) ?? 0.0,
        },
        equipment: {
          'excavator_used': {'hours': double.tryParse(_excavatorUsedController.text) ?? 0.0},
          'excavator_idle': {'hours': double.tryParse(_excavatorIdleController.text) ?? 0.0},
        },
        laborHours: 0.0,
        notes: _notesController.text,
        weatherCondition: _selectedWeather,
        createdAt: DateTime.now(),
      );

      await ref.read(resourceLogServiceProvider).addLog(log, photo: _image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Log Evidence Recorded for \${widget.projectId}'), backgroundColor: DFColors.primaryStitch),
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

  @override
  Widget build(BuildContext context) {
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
                  _buildHeaderInfo(),
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle('inventory_2', 'Materials Consumption'),
                  const SizedBox(height: 16),
                  _buildMaterialGrid(),
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle('construction', 'Equipment Utilization'),
                  const SizedBox(height: 16),
                  _buildEquipmentSection(),
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
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: DFColors.primaryContainerStitch, shape: BoxShape.circle),
                clipBehavior: Clip.hardEdge,
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.notifications_outlined, color: DFColors.primaryStitch),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Log for Block-A', style: DFTextStyles.screenTitle.copyWith(color: DFColors.primaryStitch, fontSize: 24, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('Phase 2: Structural Reinforcement', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
              ],
            ),
          ],
        ),
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
          children: [
            _buildWeatherChip('Sunny', Icons.sunny, 'Sunny'),
            _buildWeatherChip('Cloudy', Icons.cloud, 'Cloudy'),
            _buildWeatherChip('Rainy', Icons.water_drop, 'Rainy'),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherChip(String label, IconData icon, String value) {
    bool isSelected = _selectedWeather == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedWeather = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEA619) : DFColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF684000) : DFColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: DFTextStyles.body.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF684000) : DFColors.textSecondary,
            )),
          ],
        ),
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

  Widget _buildMaterialGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildMaterialCard('Cement (PPC)', 'Est: ~38 bags', 'bags', Icons.conveyor_belt, _cementController, warning: 'Exceeds estimate (1.1x)')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildMaterialCard('Steel Rebar 12mm', 'Est: ~120 nos', 'nos', Icons.architecture, _rebarController, warning: 'Over 1.2x limit', isCritical: true)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildMaterialCard('Admixture', 'Est: ~15 kg', 'kg', Icons.water_drop, _admixtureController)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildMaterialCard('River Sand', 'Est: ~4.5 m³', 'm³', Icons.texture, _sandController)),
          ],
        ),
      ],
    );
  }

  Widget _buildMaterialCard(String title, String est, String unit, IconData iconData, TextEditingController controller, {String? warning, bool isCritical = false}) {
    Color borderColor = isCritical ? const Color(0xFFFEA619).withValues(alpha: 0.3) : Colors.transparent;
    double borderWidth = isCritical ? 2.0 : 0.0;
    Color inputBg = isCritical ? const Color(0xFFFEA619).withValues(alpha: 0.1) : DFColors.surfaceContainerHighest;
    Color inputBorderColor = isCritical ? const Color(0xFFFEA619) : Colors.transparent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: const [BoxShadow(color: Color(0x0F191C1E), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                child: Icon(iconData, color: DFColors.primaryStitch, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  Text(est, style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 100, height: 48,
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: inputBorderColor, width: isCritical ? 2 : 0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.right,
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 20),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 4),
                      child: Text(unit, style: DFTextStyles.labelSm.copyWith(color: isCritical ? const Color(0xFF653E00) : DFColors.outlineVariant, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (warning != null) ...[
                const SizedBox(height: 4),
                Text(warning, style: DFTextStyles.labelSm.copyWith(color: isCritical ? const Color(0xFF653E00) : const Color(0xFF850009), fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentSection() {
    return Container(
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildEquipmentRow('Excavator E-04', 'Heavy Duty', Icons.agriculture, _excavatorUsedController, _excavatorIdleController, '18%', const Color(0xFF059669)),
          const Divider(height: 1, color: Color(0x1Ac2c6d3)),
          _buildEquipmentRow('Tower Crane C-01', 'Lifting', Icons.precision_manufacturing, _craneUsedController, _craneIdleController, '50%', const Color(0xFF850009)),
          const Divider(height: 1, color: Color(0x1Ac2c6d3)),
          _buildEquipmentRow('Concrete Mixer M-12', 'Transit', Icons.cyclone, _mixerUsedController, _mixerIdleController, '0%', const Color(0xFF059669)),
        ],
      ),
    );
  }

  Widget _buildEquipmentRow(String title, String subtitle, IconData icon, TextEditingController usedCtrl, TextEditingController idleCtrl, String ratio, Color ratioColor) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: DFColors.primaryStitch)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  Text(subtitle.toUpperCase(), style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: DFColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('USED HRS', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: TextField(
                        controller: usedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 18),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IDLE HRS', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: TextField(
                        controller: idleCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 18),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('IDLE RATIO', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: DFColors.outlineVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(ratio, style: DFTextStyles.screenTitle.copyWith(fontSize: 18, color: ratioColor)),
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
            onPressed: _isLoading ? null : _submit,
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
      color: Colors.white.withValues(alpha: 0.6),
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
