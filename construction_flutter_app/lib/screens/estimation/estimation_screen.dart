import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/project_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../models/estimate_model.dart';
import '../../models/project_model.dart';
import '../../utils/material_rates.dart';
import '../../models/rate_library.dart';
import '../../services/rate_library_service.dart';
import '../../models/estimation_profile.dart';
import '../../services/estimation_profile_service.dart';
import '../../services/estimation_engine.dart';
import 'rate_library_screen.dart';
import 'boq_screen.dart';
import '../../widgets/charts/animated_pie_chart.dart';

class EstimationScreen extends ConsumerStatefulWidget {
  const EstimationScreen({super.key});

  @override
  ConsumerState<EstimationScreen> createState() => _EstimationScreenState();
}

class _EstimationScreenState extends ConsumerState<EstimationScreen> {
  EstimateModel? _estimation;
  bool _isGenerating = false;

  // Phase 1 live-recompute specs (PlanSwift-style what-if).
  String _brickType = 'modular_mix';
  String _tileSize = '600x600';

  // Phase 4 finish package + regional profile (null = use saved value).
  String? _packageKey;
  String? _regionKey;

  Future<void> _handleGenerate(String projectId, String? cadFileUrl) async {
    setState(() => _isGenerating = true);
    try {
      final result = await ref.read(estimationServiceProvider).generateEstimate(
        projectId,
        cadFileUrl ?? '',
      );
      setState(() {
        _estimation = result;
        // Seed the live selectors from any previously-saved specs.
        final specs = result.materialSpecs;
        if (specs != null) {
          if (specs['brickType'] is String) _brickType = specs['brickType'] as String;
          if (specs['floorTileSize'] is String) _tileSize = specs['floorTileSize'] as String;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estimation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We expect the project ID to be in the route, but for this component, 
    // we'll get the current project from the provider or state.
    // For simplicity, let's assume we are viewing the first active project 
    // or passed via route (not shown here for brevity, using mock logic)
    
    final projectsAsync = ref.watch(userProjectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Material Estimation')),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) return const Center(child: Text('No active projects'));
          final project = projects.first; // Using first one for demo
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGeometrySummary(project),
                const SizedBox(height: 32),
                if (_estimation == null)
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : () => _handleGenerate(project.id, project.cadFileUrl),
                      icon: const Icon(Icons.analytics),
                      label: const Text('GENERATE MATERIAL ESTIMATE'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  )
                else
                  _buildResultsWithProfile(_estimation!, project.id),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildGeometrySummary(ProjectModel project) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('CAD Geometry Detected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildGeoIdx('Wall Length', '${project.totalWallLength.toStringAsFixed(1)} m'),
                _buildGeoIdx('Floor Area', '${project.totalFloorArea.toStringAsFixed(1)} m²'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeoIdx(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Wraps the results with the Phase 4 profile selector and composes the
  /// finish-package + regional factors onto the project's rate library.
  Widget _buildResultsWithProfile(EstimateModel est, String projectId) {
    final saved = ref.watch(projectEstimationProfileProvider(projectId)).valueOrNull ??
        const EstimationProfile();
    final pkgKey = _packageKey ?? saved.packageKey;
    final regKey = _regionKey ?? saved.regionKey;
    final profile = EstimationProfile(packageKey: pkgKey, regionKey: regKey);
    final baseLib = ref.watch(projectRateLibraryProvider(projectId)).valueOrNull ??
        RateLibrary.defaults();
    final effLib = profile.apply(baseLib);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileSelector(projectId, pkgKey, regKey),
        _buildEstimationResults(est, projectId, effLib),
      ],
    );
  }

  void _saveProfile(String projectId, String pkg, String region) {
    ref.read(estimationProfileServiceProvider).save(
        projectId, EstimationProfile(packageKey: pkg, regionKey: region));
  }

  Widget _buildProfileSelector(String projectId, String pkgKey, String regKey) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 18, color: Colors.deepPurple),
                const SizedBox(width: 12),
                const Text('Finish package'),
                const Spacer(),
                DropdownButton<String>(
                  value: pkgKey,
                  underline: const SizedBox.shrink(),
                  items: EstimationCatalog.packages.values
                      .map((p) =>
                          DropdownMenuItem(value: p.key, child: Text(p.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final p = EstimationCatalog.packages[v]!;
                    setState(() {
                      _packageKey = v;
                      _brickType = p.brickType; // package suggests specs
                      _tileSize = p.tileSize;
                    });
                    _saveProfile(projectId, v, regKey);
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.public, size: 18, color: Colors.deepPurple),
                const SizedBox(width: 12),
                const Text('Region'),
                const Spacer(),
                DropdownButton<String>(
                  value: regKey,
                  underline: const SizedBox.shrink(),
                  items: EstimationCatalog.regions.values
                      .map((r) =>
                          DropdownMenuItem(value: r.key, child: Text(r.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _regionKey = v);
                    _saveProfile(projectId, pkgKey, v);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimationResults(
      EstimateModel est, String projectId, RateLibrary rateLib) {
    final mats = est.estimatedMaterials;

    // Bricks scale with the selected type: the saved quantity used the default
    // 90/m² coefficient, so recover the wall area and reapply the new rate.
    final double baseNetWallArea =
        est.bricks / MaterialRates.brickPerM2('modular_mix');
    final double bricksQty =
        (baseNetWallArea * MaterialRates.brickPerM2(_brickType)).roundToDouble();

    // Costs come from the per-project rate library (defaults until edited).
    // Convert m³→cu.ft for sand/aggregate so it matches the rate unit.
    double cost(String key, double qty) =>
        rateLib.materialRate(key) *
        MaterialRates.getQuantityInRateUnit(key, qty);
    final cementCost = cost('cement', est.cement);
    final bricksCost = bricksQty * rateLib.materialRate(_brickType);
    final steelCost = cost('steel', est.steel);
    final sandCost = cost('sand', est.sand);
    final aggregateCost = cost('aggregate', est.aggregate);

    final steelSched = EstimationEngine.typicalSteelSchedule(est.steel);

    // Legacy estimates have no estimationType → treat as structural.
    final bool showStructural = est.estimationType != 'interior';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Material Breakdown',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RateLibraryScreen(projectId: projectId),
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit rates'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (showStructural) ...[
          AnimatedPieChart(
            dataValues: {
              'cement': cementCost,
              'bricks': bricksCost,
              'steel': steelCost,
              'sand': sandCost,
              'aggregate': aggregateCost,
            },
          ),
          const SizedBox(height: 16),
          _buildBrickSpecSelector(),
          _buildMaterialRow('Cement', '${est.cement.toStringAsFixed(1)} ${mats['cement']?['unit'] ?? 'Bags'}', Icons.inventory),
          ListTile(
            leading: const Icon(Icons.grid_view, color: Colors.blue),
            title: const Text('Bricks'),
            subtitle: Text('${MaterialRates.brickLabel(_brickType)} · ₹${_inr(bricksCost)}'),
            trailing: Text('${bricksQty.toStringAsFixed(0)} ${MaterialRates.brickUnit(_brickType)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          _buildSteelRow(est.steel, steelSched),
          _buildMaterialRow('Sand', '${est.sand.toStringAsFixed(2)} ${mats['sand']?['unit'] ?? 'm3'}', Icons.grain),
          _buildMaterialRow('Aggregate', '${est.aggregate.toStringAsFixed(2)} ${mats['aggregate']?['unit'] ?? 'm3'}', Icons.layers),
        ],
        ..._interiorSection(est, rateLib),
        const SizedBox(height: 16),
        if (showStructural)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BoqScreen(
                  projectId: projectId,
                  geometry: Map<String, dynamic>.from(est.geometryData),
                  brickType: _brickType,
                  projectName: est.cadFileName,
                ),
              ),
            ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('VIEW DETAILED BOQ (ASSEMBLIES)'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _saveSpecsAndExit(projectId, est.estimateId),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: const Text('SAVE & FINISH'),
        ),
      ],
    );
  }

  /// Persist the chosen specs onto the estimate doc, then exit. Best-effort:
  /// a missing/ephemeral estimate just skips the write rather than erroring.
  Future<void> _saveSpecsAndExit(String projectId, String estimateId) async {
    final specs = {'brickType': _brickType, 'floorTileSize': _tileSize};
    try {
      await FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .collection('estimates')
          .doc(estimateId)
          .set({'materialSpecs': specs}, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal — specs persistence is a convenience, not required to exit.
    }
    if (mounted) context.pop();
  }

  /// Live brick/block type selector — recomputes brick quantity & cost.
  Widget _buildBrickSpecSelector() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 12),
            const Text('Brick / block type'),
            const Spacer(),
            DropdownButton<String>(
              value: _brickType,
              underline: const SizedBox.shrink(),
              items: MaterialRates.brickTypes.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value['label'] as String)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _brickType = v);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Steel row that expands into a typical bar-bending schedule by diameter.
  Widget _buildSteelRow(double totalKg, Map<String, double> sched) {
    return ExpansionTile(
      leading: const Icon(Icons.reorder, color: Colors.blue),
      title: const Text('Steel'),
      subtitle: const Text('tap for bar schedule (typical distribution)',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
      trailing: Text('${totalKg.toStringAsFixed(1)} Kg',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      children: sched.entries
          .map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ø ${e.key}', style: const TextStyle(color: Colors.grey)),
                    Text('${e.value.toStringAsFixed(1)} kg'),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMaterialRow(String name, String qty, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(name),
      trailing: Text(qty, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  List<Widget> _interiorSection(EstimateModel est, RateLibrary rateLib) {
    final interior = est.interiorMaterials;
    if (interior == null ||
        interior.isEmpty ||
        est.estimationType == 'structural') {
      return const [];
    }
    double total = 0;
    final bool hasTiles = interior.containsKey('floor_tiles') ||
        interior.containsKey('wall_dado_tiles');
    final rows = <Widget>[
      const SizedBox(height: 16),
      const Text('Interior / Finishes',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (hasTiles) _buildTileSpecSelector(),
    ];
    interior.forEach((key, data) {
      final qty = ((data?['quantity'] ?? 0) as num).toDouble();
      final unit = (data?['unit'] ?? '').toString();
      final cost = rateLib.materialRate(key) * qty;
      total += cost;
      final qtyStr = qty == qty.roundToDouble()
          ? qty.toInt().toString()
          : qty.toStringAsFixed(1);
      // Floor + dado tiles carry a 10% cutting-wastage allowance. Surface the
      // base area (qty ÷ 1.10) so the quantity isn't mistaken for a mismatch
      // with the floor area.
      String subtitle = '₹${_inr(cost)}';
      if (key == 'floor_tiles' || key == 'wall_dado_tiles') {
        final baseArea = qty / 1.10;
        final boxes = (qty / MaterialRates.tileM2PerBox(_tileSize)).ceil();
        subtitle = '₹${_inr(cost)}  ·  ${baseArea.toStringAsFixed(1)} m² + 10% wastage'
            '  ·  $boxes boxes (${MaterialRates.tileLabel(_tileSize)})';
      }
      rows.add(ListTile(
        dense: true,
        leading: Icon(_interiorIcon(key), color: Colors.teal),
        title: Text(MaterialRates.interiorLabel(key)),
        subtitle: Text(subtitle),
        trailing: Text('$qtyStr $unit',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ));
    });
    rows.add(ListTile(
      title: const Text('Interior Total',
          style: TextStyle(fontWeight: FontWeight.bold)),
      trailing: Text('₹${_inr(total)}',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
    ));
    return rows;
  }

  /// Live tile-size selector — recomputes box counts for floor/dado tiles.
  Widget _buildTileSpecSelector() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.straighten, size: 18, color: Colors.teal),
            const SizedBox(width: 12),
            const Text('Tile size'),
            const Spacer(),
            DropdownButton<String>(
              value: _tileSize,
              underline: const SizedBox.shrink(),
              items: MaterialRates.tileSizes.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value['label'] as String)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tileSize = v);
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _interiorIcon(String key) {
    switch (key) {
      case 'floor_tiles':
        return Icons.grid_on;
      case 'skirting':
        return Icons.border_bottom;
      case 'wall_dado_tiles':
        return Icons.dashboard_customize;
      case 'wall_putty':
      case 'primer':
      case 'emulsion_paint':
        return Icons.format_paint;
      case 'wc':
        return Icons.wc;
      case 'washbasin':
        return Icons.bathtub_outlined;
      case 'shower_tap_set':
        return Icons.shower;
      case 'kitchen_sink':
        return Icons.kitchen;
      case 'light_points':
        return Icons.lightbulb_outline;
      case 'fan_points':
        return Icons.mode_fan_off;
      case 'socket_points':
        return Icons.power;
      case 'switch_boards':
        return Icons.toggle_on;
      default:
        return Icons.handyman;
    }
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
}
