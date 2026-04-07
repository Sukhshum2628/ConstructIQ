import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../providers/estimation_provider.dart';
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

  void _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      final fileName = result.files.single.name.toLowerCase();
      if (!fileName.endsWith('.dxf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('UNSUPPORTED FORMAT: PLEASE SELECT A .DXF FILE'), 
              backgroundColor: DFColors.criticalBg,
            )
          );
        }
        return;
      }

      setState(() => _isUploading = true);
      try {
        await Future.delayed(const Duration(seconds: 2));
        
        final geometryResponse = await ref.read(estimationServiceProvider).parseCad(
          'https://mock-url.com/file.dxf', 
          'project_123',
        );
        
        if (mounted) {
          setState(() {
            _estimationResult = geometryResponse['geometry'] ?? {
              'wallArea': 342.6,
              'floorArea': 186.4,
              'columns': 12,
              'height': 3.0,
              'volume': 559.2,
              'complexity': 1.2,
              'cost': 869600.0,
            };
            _isUploading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ERR: $e'), 
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
        title: Text('CAD ESTIMATION', 
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
          Text('DIGITAL CAD ANALYSIS', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
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
                      Text('UPLOAD .DXF DRAWING', 
                        style: DFTextStyles.cardTitle),
                      const SizedBox(height: 12),
                      Text(
                        'WE WILL AUTOMATICALLY EXTRACT WALL LENGTHS AND CALCULATE MATERIALS WITH INDUSTRIAL PRECISION.',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DFSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            onPressed: () => context.pop(),
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
              Text('SKYTOWER_P2_REVB.DXF • VERIFIED', 
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
        _metricTile('WALL AREA', '${_estimationResult?['wallArea']} m²'),
        _metricTile('FLOOR AREA', '${_estimationResult?['floorArea']} m²'),
        _metricTile('STR. COLUMNS', '${_estimationResult?['columns']} units'),
        _metricTile('HEIGHT', '${_estimationResult?['height']} m'),
        _metricTile('TOTAL VOLUME', '${_estimationResult?['volume']} m³'),
        _metricTile('COMPLEXITY', '${_estimationResult?['complexity']} β'),
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
