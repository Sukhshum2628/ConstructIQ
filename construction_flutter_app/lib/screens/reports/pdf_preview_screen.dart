import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/design_tokens.dart';
import '../../models/project_model.dart';
import '../../models/estimate_model.dart';
import '../../models/deviation_model.dart';
import '../../services/report_service.dart';
import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/estimation_provider.dart';

class PdfPreviewScreen extends ConsumerWidget {
  final String projectId;

  const PdfPreviewScreen({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));
    final deviationAsync = ref.watch(latestDeviationProvider(projectId));
    final estimateService = ref.watch(estimationServiceProvider);

    return projectAsync.when(
      data: (project) {
        if (project == null) return const Scaffold(body: Center(child: Text('DATA ERROR: PROJECT NOT FOUND')));
        
        return deviationAsync.when(
          data: (deviationData) {
            final deviation = DeviationModel.fromJson(deviationData ?? {});
            
            return FutureBuilder<List<EstimateModel>>(
              future: estimateService.getProjectEstimates(projectId),
              builder: (context, snapshot) {
                final estimate = (snapshot.data != null && snapshot.data!.isNotEmpty) ? snapshot.data!.first : null;
                return _buildPreview(context, project, estimate, deviation);
              },
            );
          },
          loading: () => const Scaffold(backgroundColor: DFColors.background, body: Center(child: CircularProgressIndicator(color: DFColors.primary))),
          error: (e, _) => Scaffold(backgroundColor: DFColors.background, body: Center(child: Text('DATA ERROR: DEVIATION FETCH FAILURE', style: DFTextStyles.body.copyWith(color: DFColors.critical)))),
        );
      },
      loading: () => const Scaffold(backgroundColor: DFColors.background, body: Center(child: CircularProgressIndicator(color: DFColors.primary))),
      error: (e, _) => Scaffold(backgroundColor: DFColors.background, body: Center(child: Text('DATA ERROR: PROJECT FETCH FAILURE', style: DFTextStyles.body.copyWith(color: DFColors.critical)))),
    );
  }

  Widget _buildPreview(BuildContext context, ProjectModel project, EstimateModel? estimate, DeviationModel deviation) {
    final reportService = ReportService();
    
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB), // Gray document background
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DFColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text('Report Preview', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
        actions: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: DFColors.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, size: 18, color: DFColors.textSecondary),
          ),
          const SizedBox(width: DFSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          // A4 Document Canvas (scrollable)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DFSpacing.lg),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 850),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.08), blurRadius: 32, offset: Offset(0, 12))],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDocumentHeader(project),
                      const SizedBox(height: 32),
                      _buildBentoDataGrid(project, deviation),
                      const SizedBox(height: 32),
                      _buildMaterialEstimatesTable(estimate),
                      const SizedBox(height: 32),
                      _buildDeviationSummary(project, deviation),
                      const SizedBox(height: 48),
                      _buildDocumentFooter(project),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom Action Bar
          _buildBottomActionBar(context, reportService, project, estimate, deviation),
        ],
      ),
    );
  }

  Widget _buildDocumentHeader(ProjectModel project) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ConstructIQ branding
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf, color: DFColors.primaryContainer, size: 20),
                  const SizedBox(width: 8),
                  Text('ConstructIQ', style: DFTextStyles.body.copyWith(fontSize: 16, fontWeight: FontWeight.w900, color: DFColors.primaryContainer)),
                ],
              ),
              const SizedBox(height: 12),
              Text(project.name, style: DFTextStyles.screenTitle.copyWith(fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.visible),
              const SizedBox(height: 4),
              Text('Project Analysis Report | Jan-Dec 2026', style: DFTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text('ACTIVE', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A), letterSpacing: 0.5)),
            ),
            const SizedBox(height: 8),
            Text('Gen: ${_formatDate(DateTime.now())}', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildBentoDataGrid(ProjectModel project, DeviationModel deviation) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ML Overrun Probability Hero
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DFColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text('ML OVERRUN PROBABILITY', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: DFColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('${(deviation.mlOverrunProbability * 100).toStringAsFixed(0)}%', style: DFTextStyles.metricHero.copyWith(fontSize: 48, fontWeight: FontWeight.w900, color: deviation.mlOverrunProbability > 0.5 ? DFColors.critical : DFColors.normal)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: deviation.mlOverrunProbability > 0.5 ? const Color(0xFFB10010) : DFColors.normal,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        deviation.mlOverrunProbability > 0.5 ? 'HIGH RISK' : deviation.mlOverrunProbability > 0.3 ? 'MODERATE' : 'LOW RISK',
                        style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // AI Risk Assessment Summary
            Expanded(
              flex: 8,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DFColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smart_toy, color: DFColors.primaryContainer, size: 18),
                        const SizedBox(width: 8),
                        Text('AI Risk Assessment', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      deviation.aiInsightSummary.isNotEmpty
                          ? deviation.aiInsightSummary
                          : 'No AI risk assessment available for this project yet. Run a deviation analysis to generate insights.',
                      style: DFTextStyles.body.copyWith(fontSize: 13, height: 1.6, color: DFColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMaterialEstimatesTable(EstimateModel? estimate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2, color: DFColors.primaryContainer, size: 18),
            const SizedBox(width: 8),
            Text('Material Estimates vs Actuals', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                color: DFColors.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text('RESOURCE TYPE', style: _tableHeaderStyle())),
                    Expanded(flex: 2, child: Text('ESTIMATED', style: _tableHeaderStyle())),
                    Expanded(flex: 2, child: Text('ACTUAL TO DATE', style: _tableHeaderStyle())),
                    Expanded(flex: 1, child: Text('VARIANCE', style: _tableHeaderStyle().copyWith(height: 1), textAlign: TextAlign.right)),
                  ],
                ),
              ),
              // Dynamic material rows from estimate
              if (estimate != null && estimate.estimatedMaterials.isNotEmpty)
                ...estimate.estimatedMaterials.entries.map((entry) {
                  final name = entry.key[0].toUpperCase() + entry.key.substring(1);
                  final qty = entry.value['quantity'];
                  final unit = entry.value['unit'] ?? '';
                  final qtyStr = qty is num ? qty.toStringAsFixed(0) : qty.toString();
                  return Column(
                    children: [
                      _buildTableRow(name, '$qtyStr $unit', '--', '--', false),
                      const Divider(height: 1, color: DFColors.surfaceContainerHigh),
                    ],
                  );
                })
              else ...[  
                _buildTableRow('No estimate data', '--', '--', '--', false),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  TextStyle _tableHeaderStyle() {
    return DFTextStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: DFColors.textPrimary);
  }

  Widget _buildTableRow(String resource, String estimated, String actual, String variance, bool isNegative) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(resource, style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text(estimated, style: DFTextStyles.body.copyWith(fontSize: 12))),
          Expanded(flex: 2, child: Text(actual, style: DFTextStyles.body.copyWith(fontSize: 12))),
          Expanded(
            flex: 1,
            child: Text(
              variance,
              textAlign: TextAlign.right,
              style: DFTextStyles.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isNegative ? DFColors.critical : const Color(0xFF16A34A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviationSummary(ProjectModel project, DeviationModel deviation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber, color: DFColors.primaryContainer, size: 18),
            const SizedBox(width: 8),
            Text('Deviation Summary', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: isWide ? (constraints.maxWidth - 12) / 2 : double.infinity,
                  child: _buildDeviationCard(
                    'CRITICAL FLAG',
                    '#9901',
                    'Structural Steel Grade Mismatch',
                    'Batch #A4-22 fails to meet tensile specifications by 4%. Immediate stoppage on level 4.',
                    DFColors.critical,
                  ),
                ),
                SizedBox(
                  width: isWide ? (constraints.maxWidth - 12) / 2 : double.infinity,
                  child: _buildDeviationCard(
                    'WARNING FLAG',
                    '#8721',
                    'Curing Timeline Deviation',
                    'Humidity levels exceeding 85% on Sector 62 site causing 24hr curing lag.',
                    DFColors.warning,
                  ),
                ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildDeviationCard(String label, String incidentId, String title, String description, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Flexible(child: Text('ID: $incidentId', style: DFTextStyles.caption.copyWith(fontSize: 9, color: DFColors.textSecondary), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(description, style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildDocumentFooter(ProjectModel project) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: DFColors.surfaceContainerHigh, width: 1))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('ConstructIQ Enterprise | Site Intelligence', style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w500, color: DFColors.textSecondary), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Ref: CQ-2023-B62A-R8 | Page 1/1', textAlign: TextAlign.right, style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w500, color: DFColors.textSecondary), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context, ReportService service, ProjectModel project, EstimateModel? estimate, DeviationModel deviation) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.1), blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: Row(
        children: [
          // Print button
          Expanded(
            child: _buildActionButton(Icons.print, 'Print', false, () {
              final doc = service.generatePdfDocument(project, estimate, deviation);
              service.exportPdf(doc);
            }),
          ),
          const SizedBox(width: 12),
          // Share button
          Expanded(
            child: _buildActionButton(Icons.share, 'Share', false, () {
              final doc = service.generatePdfDocument(project, estimate, deviation);
              service.sharePdf(doc, 'Construction_Report_${project.name.replaceAll(' ', '_')}');
            }),
          ),
          const SizedBox(width: 12),
          // Download PDF button (primary, wider)
          Expanded(
            flex: 2,
            child: _buildActionButton(Icons.download, 'Download PDF', true, () {
              final doc = service.generatePdfDocument(project, estimate, deviation);
              service.exportPdf(doc);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, bool isPrimary, VoidCallback onPressed) {
    return Material(
      color: isPrimary ? DFColors.primaryContainer : DFColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      elevation: isPrimary ? 4 : 0,
      shadowColor: isPrimary ? DFColors.primaryContainer.withValues(alpha: 0.2) : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isPrimary ? Colors.white : const Color(0xFF00468C)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: DFTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isPrimary ? Colors.white : const Color(0xFF00468C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
