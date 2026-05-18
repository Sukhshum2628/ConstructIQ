import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../models/project_model.dart';
import '../../models/deviation_model.dart';
import '../../utils/design_tokens.dart';
import '../../utils/report_generator.dart';
import '../../providers/auth_provider.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(userProjectsProvider);

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
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _ProjectReportCard(project: projects[index]),
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

  const _ProjectReportCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    
    // Fetch live data for the report
    final materialCost = ref.watch(estimatedCostProvider(project.projectId));
    final invoicedTotal = ref.watch(invoicedTotalProvider(project.projectId));
    final deviationAsync = ref.watch(deviationProvider(project.projectId));
    final managerName = ref.watch(userNameProvider(project.createdBy)).value ?? 'Loading...';

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
                      child: _buildMetricItem('Est. CAD Materials', currencyFormat.format(materialCost), Icons.architecture),
                    ),
                    Container(width: 1, height: 50, color: DFColors.outline),
                    Expanded(
                      child: _buildMetricItem('Total Invoiced', currencyFormat.format(invoicedTotal), Icons.receipt_long, color: invoicedTotal > materialCost ? DFColors.critical : DFColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // Deviations / AI Insight Snippet
                deviationAsync.when(
                  data: (dev) {
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
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Error loading deviations'),
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
                deviationAsync.maybeWhen(
                  data: (dev) => ElevatedButton.icon(
                    onPressed: () => _generateDetailedReport(project, managerName, materialCost, invoicedTotal, dev),
                    icon: const Icon(Icons.picture_as_pdf, size: 18, color: Colors.white),
                    label: const Text('Export PDF Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DFColors.primaryStitch,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                  orElse: () => const ElevatedButton(
                    onPressed: null,
                    child: Text('Loading Data...'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
