import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/design_tokens.dart';
import '../../utils/ui_config.dart';
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
        if (project == null)
          return const Scaffold(
              body: Center(child: Text('DATA ERROR: PROJECT NOT FOUND')));

        return deviationAsync.when(
          data: (deviationData) {
            final deviation = DeviationModel.fromJson(deviationData ?? {});

            return FutureBuilder<List<EstimateModel>>(
              future: estimateService.getProjectEstimates(projectId),
              builder: (context, snapshot) {
                final estimate =
                    (snapshot.data != null && snapshot.data!.isNotEmpty)
                        ? snapshot.data!.first
                        : null;
                return _buildPreview(context, project, estimate, deviation);
              },
            );
          },
          loading: () => const Scaffold(
              backgroundColor: DFColors.background,
              body: Center(
                  child: CircularProgressIndicator(color: DFColors.primary))),
          error: (e, _) => Scaffold(
              backgroundColor: DFColors.background,
              body: Center(
                  child: Text('DATA ERROR: DEVIATION FETCH FAILURE',
                      style: DFTextStyles.body
                          .copyWith(color: DFColors.critical)))),
        );
      },
      loading: () => const Scaffold(
          backgroundColor: DFColors.background,
          body: Center(
              child: CircularProgressIndicator(color: DFColors.primary))),
      error: (e, _) => Scaffold(
          backgroundColor: DFColors.background,
          body: Center(
              child: Text('DATA ERROR: PROJECT FETCH FAILURE',
                  style:
                      DFTextStyles.body.copyWith(color: DFColors.critical)))),
    );
  }

  Widget _buildPreview(BuildContext context, ProjectModel project,
      EstimateModel? estimate, DeviationModel deviation) {
    final reportService = ReportService();

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB), // Gray document background
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: DFColors.surface.withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: false,
        leadingWidth: ProjectDetailUI.appBarLeadingWidth,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: DFColors.primaryStitch),
            onPressed: () => context.pop(),
          ),
        ),
        title: Row(
          children: [
            const SizedBox(width: ProjectDetailUI.arrowToTitleGap),
            Flexible(
              child: Text(
                'Report Preview',
                overflow: TextOverflow.ellipsis,
                style: DFTextStyles.screenTitle.copyWith(
                  color: DFColors.primaryStitch,
                  fontSize: ProjectDetailUI.titleFontSize,
                  fontWeight: ProjectDetailUI.titleWeight,
                  letterSpacing: ProjectDetailUI.titleLetterSpacing,
                ),
              ),
            ),
          ],
        ),
        actions: [],
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
                    boxShadow: const [
                      BoxShadow(
                          color: Color.fromRGBO(25, 28, 30, 0.08),
                          blurRadius: 32,
                          offset: Offset(0, 12))
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDocumentHeader(project),
                      const SizedBox(height: 16),
                      _buildBentoDataGrid(project, deviation),
                      const SizedBox(height: 20),
                      _buildMaterialEstimatesTable(estimate),
                      const SizedBox(height: 32),
                      _buildDeviationSummary(project, deviation),
                      const SizedBox(height: 40),
                      _buildDocumentFooter(project),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom Action Bar
          _buildBottomActionBar(
              context, reportService, project, estimate, deviation),
        ],
      ),
    );
  }

  Widget _buildDocumentHeader(ProjectModel project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Layer 1: Project Name + Date as subscript
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              style: DFTextStyles.screenTitle.copyWith(
                color: DFColors.primaryStitch,
                fontSize: ProjectDetailUI.titleFontSize,
                fontWeight: ProjectDetailUI.titleWeight,
                letterSpacing: ProjectDetailUI.titleLetterSpacing,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(DateTime.now()),
              style: DFTextStyles.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DFColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Layer 2: Active Status
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF16A34A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'ACTIVE',
              style: DFTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Layer 3: Report Info
        Row(
          children: [
            Text(
              'Project Analysis Report',
              style: DFTextStyles.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '|',
              style: DFTextStyles.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: DFColors.outlineVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Jan-Dec 2026',
                style: DFTextStyles.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBentoDataGrid(ProjectModel project, DeviationModel deviation) {
    final mlPercentage = (deviation.mlOverrunProbability * 100).toStringAsFixed(0);
    final isHighRisk = deviation.mlOverrunProbability > 0.5;
    
    return Column(
      children: [
        // ML Overrun Probability - Horizontal Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ML OVERRUN PROBABILITY',
                    style: DFTextStyles.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: DFColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isHighRisk)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB10010),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isHighRisk
                              ? const Color(0xFFB10010)
                              : DFColors.normal,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isHighRisk
                              ? 'HIGH RISK'
                              : deviation.mlOverrunProbability > 0.3
                                  ? 'MODERATE'
                                  : 'LOW RISK',
                          style: DFTextStyles.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Percentage Circle
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: (isHighRisk ? DFColors.critical : DFColors.normal).withOpacity(0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isHighRisk ? DFColors.critical : DFColors.normal).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$mlPercentage%',
                    style: DFTextStyles.metricHero.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // AI Risk Assessment Summary - Below
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: DFColors.primaryContainer, width: 2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.smart_toy,
                    color: DFColors.primaryContainer, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Text('AI Risk Assessment',
                style: DFTextStyles.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DFColors.primaryContainer)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          deviation.aiInsightSummary.isNotEmpty
              ? deviation.aiInsightSummary
              : 'No AI risk assessment available for this project yet. Run a deviation analysis to generate insights.',
          style: DFTextStyles.body.copyWith(
              fontSize: 13,
              height: 1.6,
              color: DFColors.textPrimary),
        ),
            ],
          ),
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: DFColors.primaryContainer, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.inventory_2,
                    color: DFColors.primaryContainer, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: DFColors.outlineVariant, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Material Estimates vs Actuals',
                    style: DFTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DFColors.textPrimary)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: DFColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DFColors.outlineVariant, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: DFColors.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text('RESOURCE TYPE',
                            style: _tableHeaderStyle()),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text('ESTIMATED',
                            style: _tableHeaderStyle(),
                            textAlign: TextAlign.center),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text('ACTUAL TO DATE',
                            style: _tableHeaderStyle(),
                            textAlign: TextAlign.center),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text('VARIANCE',
                            style: _tableHeaderStyle(),
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
                if (estimate != null && estimate.estimatedMaterials.isNotEmpty)
                  ...estimate.estimatedMaterials.entries.map((entry) {
                    final name =
                        entry.key[0].toUpperCase() + entry.key.substring(1);
                    final qty = entry.value['quantity'];
                    final unit = entry.value['unit'] ?? '';
                    final qtyStr =
                        qty is num ? qty.toStringAsFixed(0) : qty.toString();
                    return _buildTableRowCompact(name, '$qtyStr $unit', '--', '--');
                  })
                else ...[
                  _buildTableRowCompact('No estimate data', '--', '--', '--'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  TextStyle _tableHeaderStyle() {
    return DFTextStyles.caption.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: DFColors.textPrimary);
  }

  Widget _buildTableRowCompact(String resource, String estimated,
      String actual, String variance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: DFColors.surfaceContainerHigh.withOpacity(0.5), width: 1),
        ),
      ),
      child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(resource,
                  style: DFTextStyles.body.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 110,
              child: Text(estimated,
                  style: DFTextStyles.body.copyWith(fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            SizedBox(
              width: 120,
              child: Text(actual,
                  style: DFTextStyles.body.copyWith(fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            SizedBox(
              width: 90,
              child: Text(variance,
                  style: DFTextStyles.body.copyWith(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right),
            ),
          ],
        ),
    );
  }

  @Deprecated('Use _buildTableRowCompact instead')
  Widget _buildTableRow(String resource, String estimated, String actual,
      String variance, bool isNegative) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(resource,
                  style: DFTextStyles.body
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(
              flex: 2,
              child: Text(estimated,
                  style: DFTextStyles.body.copyWith(fontSize: 13))),
          Expanded(
              flex: 2,
              child: Text(actual,
                  style: DFTextStyles.body.copyWith(fontSize: 13))),
          Expanded(
            flex: 1,
            child: Text(
              variance,
              textAlign: TextAlign.right,
              style: DFTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isNegative ? DFColors.critical : const Color(0xFF16A34A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviationSummary(
      ProjectModel project, DeviationModel deviation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: DFColors.primaryContainer, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.warning_amber,
                    color: DFColors.primaryContainer, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: DFColors.outlineVariant, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Deviation Summary',
                    style: DFTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DFColors.textPrimary)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 500;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width:
                    isWide ? (constraints.maxWidth - 12) / 2 : double.infinity,
                child: _buildDeviationCard(
                  'CRITICAL FLAG',
                  '#9901',
                  'Structural Steel Grade Mismatch',
                  'Batch #A4-22 fails to meet tensile specifications by 4%. Immediate stoppage on level 4.',
                  DFColors.critical,
                ),
              ),
              SizedBox(
                width:
                    isWide ? (constraints.maxWidth - 12) / 2 : double.infinity,
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
        }),
      ],
    );
  }

  Widget _buildDeviationCard(String label, String incidentId, String title,
      String description, Color color) {
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
              Flexible(
                  child: Text(label,
                      style: DFTextStyles.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color),
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Flexible(
                  child: Text('ID: $incidentId',
                      style: DFTextStyles.caption
                          .copyWith(fontSize: 9, color: DFColors.textSecondary),
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: DFTextStyles.body
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(description,
              style: DFTextStyles.caption.copyWith(
                  fontSize: 11, color: DFColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildDocumentFooter(ProjectModel project) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: DFColors.surfaceContainerHigh, width: 1))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('ConstructIQ Enterprise | Site Intelligence',
                style: DFTextStyles.caption.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: DFColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Ref: CQ-2023-B62A-R8 | Page 1/1',
                textAlign: TextAlign.right,
                style: DFTextStyles.caption.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: DFColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context, ReportService service,
      ProjectModel project, EstimateModel? estimate, DeviationModel deviation) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        boxShadow: const [
          BoxShadow(
              color: Color.fromRGBO(25, 28, 30, 0.1),
              blurRadius: 24,
              offset: Offset(0, -4))
        ],
      ),
      child: Row(
        children: [
          // Print button
          Expanded(
            child: _buildActionButton(Icons.print, 'Print', false, () {
              final doc =
                  service.generatePdfDocument(project, estimate, deviation);
              service.exportPdf(doc);
            }),
          ),
          const SizedBox(width: 12),
          // Share button
          Expanded(
            child: _buildActionButton(Icons.share, 'Share', false, () {
              final doc =
                  service.generatePdfDocument(project, estimate, deviation);
              service.sharePdf(doc,
                  'Construction_Report_${project.name.replaceAll(' ', '_')}');
            }),
          ),
          const SizedBox(width: 12),
          // Download PDF button (primary, wider)
          Expanded(
            flex: 2,
            child: _buildActionButton(Icons.download, 'Download PDF', true, () {
              final doc =
                  service.generatePdfDocument(project, estimate, deviation);
              service.exportPdf(doc);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, bool isPrimary, VoidCallback onPressed) {
    return Material(
      color:
          isPrimary ? DFColors.primaryContainer : DFColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      elevation: isPrimary ? 4 : 0,
      shadowColor: isPrimary
          ? DFColors.primaryContainer.withValues(alpha: 0.2)
          : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: isPrimary ? Colors.white : const Color(0xFF00468C)),
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
