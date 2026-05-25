import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/ml_cache_provider.dart';
import '../../models/project_model.dart';
import '../../models/deviation_model.dart';
import '../../utils/design_tokens.dart';
import '../../utils/report_generator.dart';
import '../../providers/auth_provider.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _staggeredTriggered = false;

  void _triggerStaggeredLoading(List<ProjectModel> projects, WidgetRef ref) {
    if (_staggeredTriggered) return;
    _staggeredTriggered = true;
    for (int i = 0; i < projects.length; i++) {
      final projectId = projects[i].projectId;
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) {
          _loadPredictionIfNeeded(projectId, ref);
        }
      });
    }
  }

  void _loadPredictionIfNeeded(String projectId, WidgetRef ref) {
    final cache = ref.read(mlCacheProvider.notifier);
    
    // Skip if already computed or currently loading
    if (cache.isComputed(projectId) || cache.isLoading(projectId)) {
      return;
    }

    // Mark as loading immediately
    cache.markLoading(projectId);

    // Run in background — do not await in build method
    _computePrediction(projectId, ref);
  }

  Future<void> _computePrediction(String projectId, WidgetRef ref) async {
    try {
      // Get deviation data for this project (triggers prediction inside)
      final deviationResult = await ref.read(
        deviationProvider(projectId).future
      );
      
      // Delay slightly to prevent concurrent ONNX calls
      await Future.delayed(const Duration(milliseconds: 100));
      
      final probability = deviationResult.mlOverrunProbability;
      final severity = deviationResult.overallSeverity;
      
      ref.read(mlCacheProvider.notifier).setResult(
        projectId, probability, severity, deviationResult
      );
    } catch (e) {
      debugPrint('Prediction failed for $projectId: $e');
      ref.read(mlCacheProvider.notifier).setError(projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(userProjectsProvider);

    // Trigger staggered initial load of ML predictions once projects are loaded (FIX 3)
    projectsAsync.whenData((projects) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerStaggeredLoading(projects, ref);
      });
    });

    return Scaffold(
      backgroundColor: DFColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: DFColors.surface,
            elevation: 0,
            title: Text('Reports & Insights', style: DFTextStyles.screenTitle),
          ),
          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text('No active projects found for reporting.')),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final project = projects[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _ProjectReportCard(
                          key: ValueKey(project.projectId),
                          project: project,
                        ),
                      );
                    },
                    childCount: projects.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error loading projects: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectReportCard extends ConsumerWidget {
  final ProjectModel project;

  const _ProjectReportCard({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    
    // Fetch live data for the report
    final estimateAsync = ref.watch(latestEstimateProvider(project.projectId));
    final estimate = estimateAsync.valueOrNull;
    final rawMaterialCost = ref.watch(estimatedCostProvider(project.projectId));
    final displayMaterialCost = estimate?.manualMaterialCost ?? rawMaterialCost;
    final invoicedTotal = ref.watch(invoicedTotalProvider(project.projectId));
    final managerName = ref.watch(userNameProvider(project.createdBy)).valueOrNull ?? 'Loading...';

    // Read from persistent cache (FIX 2 & 4)
    final cacheState = ref.watch(mlCacheProvider);
    final isLoading = cacheState.loading.contains(project.projectId);
    final isComputed = cacheState.computed.contains(project.projectId);
    final devResult = cacheState.results[project.projectId];

    return Container(
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DFColors.primaryStitch.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: DFColors.primaryStitch.withOpacity(0.1),
                  child: const Icon(Icons.analytics_rounded, color: DFColors.primaryStitch),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.name, style: DFTextStyles.cardTitle.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Managed by: $managerName', style: DFTextStyles.caption),
                    ],
                  ),
                ),
                _buildStatusBadge(project.status.name),
              ],
            ),
          ),
          
          // Data Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildMetricItem('Est. CAD Materials', currencyFormat.format(displayMaterialCost), Icons.architecture),
                    ),
                    Container(width: 1, height: 50, color: DFColors.outline),
                    Expanded(
                      child: _buildMetricItem('Total Invoiced', currencyFormat.format(invoicedTotal), Icons.receipt_long, color: invoicedTotal > displayMaterialCost ? DFColors.critical : DFColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // Show loading only on first load, show cached value on return
                if (!isComputed && !isLoading)
                  const SizedBox(
                    height: 50,
                    child: Center(child: Text('Staggered loading queued...', style: TextStyle(color: DFColors.textSecondary))),
                  )
                else if (isLoading && devResult == null)
                  const SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
                  )
                else if (devResult != null)
                  _buildDeviationSnippet(devResult)
                else
                  const SizedBox(
                    height: 50,
                    child: Center(child: Text('Error loading deviations')),
                  ),
              ],
            ),
          ),

          // Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: DFColors.outline)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (devResult != null)
                  ElevatedButton.icon(
                    onPressed: () => _generateDetailedReport(project, managerName, displayMaterialCost, invoicedTotal, devResult),
                    icon: const Icon(Icons.picture_as_pdf, size: 18, color: Colors.white),
                    label: const Text('Export PDF Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DFColors.primaryStitch,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  )
                else
                  const ElevatedButton(
                    onPressed: null,
                    child: Text('Loading Data...'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviationSnippet(DeviationResult dev) {
    final isHealthy = dev.overallSeverity == 'normal';
    final devCount = dev.perMaterial.length;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(isHealthy ? Icons.check_circle : Icons.warning_amber_rounded, color: isHealthy ? DFColors.success : DFColors.warning, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Analytics & Deviations', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                isHealthy ? 'Project is stable. Resource utilization matches CAD estimates.' : '$devCount materials showing critical usage deviations. Review immediately.',
                style: DFTextStyles.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: DFColors.primaryStitch.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DFColors.primaryStitch.withOpacity(0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: DFTextStyles.caption.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, {Color color = DFColors.textPrimary}) {
    return Column(
      children: [
        Icon(icon, size: 24, color: DFColors.textSecondary),
        const SizedBox(height: 8),
        Text(value, style: DFTextStyles.cardTitle.copyWith(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: DFTextStyles.caption, textAlign: TextAlign.center),
      ],
    );
  }

  void _generateDetailedReport(ProjectModel project, String managerName, double estCost, double invTotal, DeviationResult dev) {
    ReportGenerator.generateProjectReport(
      project: project,
      managerName: managerName,
      estimatedCost: estCost,
      invoicedTotal: invTotal,
      deviation: dev,
    );
  }
}
