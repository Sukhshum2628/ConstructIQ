import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../providers/project_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../models/estimate_model.dart';
import '../../models/project_model.dart';

class EstimationScreen extends ConsumerStatefulWidget {
  const EstimationScreen({super.key});

  @override
  ConsumerState<EstimationScreen> createState() => _EstimationScreenState();
}

class _EstimationScreenState extends ConsumerState<EstimationScreen> {
  EstimateModel? _estimation;
  bool _isGenerating = false;

  Future<void> _handleGenerate(String projectId, String? cadFileUrl) async {
    setState(() => _isGenerating = true);
    try {
      final result = await ref.read(estimationServiceProvider).generateEstimate(
        projectId,
        cadFileUrl ?? '',
      );
      setState(() => _estimation = result);
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
                  _buildEstimationResults(_estimation!),
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

  Widget _buildEstimationResults(EstimateModel est) {
    final mats = est.estimatedMaterials;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Material Breakdown', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: [
                PieChartSectionData(color: Colors.blue, value: (mats['cement']?['quantity'] ?? 0).toDouble(), title: 'Cement', radius: 50, showTitle: false),
                PieChartSectionData(color: Colors.orange, value: (mats['bricks']?['quantity'] ?? 0).toDouble() / 100, title: 'Bricks', radius: 50, showTitle: false),
                PieChartSectionData(color: Colors.green, value: 50.0, title: 'Sand', radius: 50, showTitle: false), // Placeholder for Sand
                PieChartSectionData(color: Colors.red, value: (mats['steel']?['quantity'] ?? 0).toDouble() / 10, title: 'Steel', radius: 50, showTitle: false),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildMaterialRow('Cement', '${mats['cement']?['quantity'] ?? 0} ${mats['cement']?['unit'] ?? 'Bags'}', Icons.inventory),
        _buildMaterialRow('Bricks', '${mats['bricks']?['quantity'] ?? 0} ${mats['bricks']?['unit'] ?? 'Nos'}', Icons.grid_view),
        _buildMaterialRow('Steel', '${mats['steel']?['quantity'] ?? 0} ${mats['steel']?['unit'] ?? 'Kg'}', Icons.reorder),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: const Text('SAVE & FINISH'),
        ),
      ],
    );
  }

  Widget _buildMaterialRow(String name, String qty, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(name),
      trailing: Text(qty, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
