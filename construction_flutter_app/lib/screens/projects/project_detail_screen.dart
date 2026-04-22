import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/estimation_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/user_model.dart';
import '../../models/project_model.dart';
import '../../models/estimate_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_pill.dart';
import '../../providers/ml_provider.dart';
import '../../utils/ui_config.dart';
import '../../utils/material_rates.dart';
import '../../services/report_service.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../models/vendor_bill_model.dart';
import '../../models/resource_log_model.dart';
import '../../models/deviation_model.dart';
import '../../services/project_service.dart';
import '../../services/estimation_service.dart';
import 'package:url_launcher/url_launcher.dart';

extension StringExtension on String {
  String capitalize() => length > 0 ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  int _activeTabIndex = 0;
  bool _isUploadingInvoice = false;

  void _pickInvoice(ProjectModel project) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      if (!mounted) return;
      setState(() => _isUploadingInvoice = true);
      try {
        final amount = await ref.read(estimationServiceProvider).extractInvoiceBudget(File(result.files.single.path!));
        final updatedProject = project.copyWith(plannedBudget: amount);
        await ref.read(projectServiceProvider).updateProject(updatedProject);
        if (!mounted) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Budget updated successfully from invoice!'),
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to process invoice: $e'),
          backgroundColor: DFColors.critical,
        ));
      } finally {
        if (mounted) setState(() => _isUploadingInvoice = false);
      }
    }
  }

  Future<void> _generateProjectReport() async {
    final project = ref.read(projectByIdProvider(widget.projectId)).value;
    if (project == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
    );

    try {
      final estimate = ref.read(latestEstimateProvider(widget.projectId)).value;
      final devData = ref.read(latestDeviationProvider(widget.projectId)).value;
      final bills = ref.read(projectBillsProvider(widget.projectId)).value ?? [];
      final logs = ref.read(projectLogsProvider(widget.projectId)).value ?? [];

      final deviation = devData != null 
          ? DeviationModel.fromJson(devData) 
          : DeviationModel(
              deviationId: '', 
              projectId: widget.projectId, 
              deviationPct: 0.0,
              zScore: 0.0,
              flagged: false,
              overallSeverity: 'normal', 
              mlOverrunProbability: 0.0,
              aiInsightSummary: 'Project is performing within expected constraints.',
              breakdown: {},
              createdAt: DateTime.now(),
            );

      final pdf = await ReportService().generatePdfDocument(
        project: project,
        estimate: estimate,
        deviation: deviation,
        bills: bills,
        logs: logs,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        await ReportService().sharePdf(pdf, '${project.name}_Analysis_Report');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to generate report: $e'),
          backgroundColor: DFColors.critical,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
    final deviationAsync = ref.watch(latestDeviationProvider(widget.projectId));
    final estimateAsync = ref.watch(latestEstimateProvider(widget.projectId));

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: DFColors.surface.withValues(alpha: 0.9),
        elevation: 0,
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
                'Project Details',
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
        actions: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon:
                const Icon(Icons.picture_as_pdf, color: DFColors.primaryStitch),
            onPressed: () =>
                context.push('/projects/${widget.projectId}/pdf-preview'),
          ),
          const SizedBox(width: ProjectDetailUI.iconGap),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.notifications_outlined,
                color: DFColors.primaryStitch),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: ProjectDetailUI.iconGap),
          Consumer(
            builder: (context, ref, _) {
              final userRole = ref.watch(userProfileProvider).value?.role;
              final project = ref.watch(projectByIdProvider(widget.projectId)).value;
              
              if ((userRole == UserRole.manager || userRole == UserRole.admin) && project?.status != ProjectStatus.closed) {
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.lock_outline_rounded, color: DFColors.primaryStitch),
                  tooltip: 'Close Project',
                  onPressed: () => _showCloseConfirmation(context, ref, project!),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: ProjectDetailUI.iconGap),
          Consumer(
            builder: (context, ref, _) {
              final userRole = ref.watch(userProfileProvider).value?.role;
              if (userRole == UserRole.manager || userRole == UserRole.admin) {
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline,
                      color: DFColors.critical),
                  onPressed: () => _showDeleteConfirmation(context, ref),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: ProjectDetailUI.actionsRightPadding),
        ],
      ),
      body: projectAsync.when(
        data: (project) {
          if (project == null)
            return const Center(child: Text('PROJECT NOT FOUND'));

          return Column(
            children: [
              if (project.status == ProjectStatus.closed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  color: DFColors.critical.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: DFColors.critical, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'THIS PROJECT IS CLOSED. DATA IS READ-ONLY.',
                          style: DFTextStyles.labelSm.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              // Tab Bar
              Container(
                color: Colors.white.withValues(alpha: 0.95),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(
                      left: ProjectDetailUI.tabLeftPadding,
                      right: ProjectDetailUI.tabRightPadding),
                  child: Row(
                    children: [
                      _buildTabItem(0, 'Overview'),
                      _buildTabItem(1, 'Estimates'),
                      _buildTabItem(2, 'Deviations'),
                      _buildTabItem(3, 'AI Chat'),
                      _buildTabItem(4, 'Bills'),
                    ],
                  ),
                ),
              ),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, ProjectDetailUI.screenTopPadding, 24, 150), 
                        child: _activeTabIndex == 0 ? _buildOverviewTab(project, estimateAsync.asData?.value, deviationAsync.asData?.value) :
                               _activeTabIndex == 1 ? _buildEstimatesTab() :
                               _activeTabIndex == 2 ? _buildDeviationsTab(project, deviationAsync.asData?.value) :
                               _activeTabIndex == 3 ? _buildAiChatTab(project) :
                               _buildBillsTab(project),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: DFColors.primaryStitch)),
        error: (e, _) => Center(
            child: Text('ERR: $e',
                style:
                    DFTextStyles.caption.copyWith(color: DFColors.critical))),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Consumer(
        builder: (context, ref, _) {
          final user = ref.watch(userProfileProvider).value;
          final userRole = user?.role;
          final isLogAuthorized = userRole == UserRole.engineer || userRole == UserRole.owner;
          final isProjectActive = projectAsync.asData?.value?.status == ProjectStatus.active;

          return Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            child: Row(
              children: [
                if (isLogAuthorized)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isProjectActive 
                        ? () => context.push('/projects/${widget.projectId}/log-entry')
                        : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isProjectActive ? DFColors.primaryStitch : DFColors.outlineVariant,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: isProjectActive ? 8 : 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isProjectActive ? Icons.add_task_rounded : Icons.lock_outline,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(isProjectActive ? 'Log Entry' : 'Project Closed',
                              style: DFTextStyles.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (isLogAuthorized) const SizedBox(width: 16),
                FloatingActionButton(
                  onPressed: () =>
                      context.push('/projects/${widget.projectId}/ai-chat'),
                  backgroundColor: DFColors.primaryStitch,
                  foregroundColor: Colors.white,
                  elevation: 12,
                  child: const Icon(Icons.smart_toy_rounded),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectHeader(
      ProjectModel project, Map<String, dynamic>? latestDev) {
    final currencyFormat =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    final dateFormat = DateFormat('MMM yyyy');

    // Calculate progress based on time
    final totalDays = project.durationDays > 0 
        ? project.durationDays 
        : project.expectedEndDate.difference(project.startDate).inDays;
        
    final now = DateTime.now();
    final start = project.startDate;
    // Calculate calendar days difference (Today = Day 1)
    final elapsedDays = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    
    final currentDay = (elapsedDays + 1).clamp(1, totalDays > 0 ? totalDays : 1);
    final timeProgress = (elapsedDays / (totalDays > 0 ? totalDays : 365)).clamp(0.0, 1.0);

    // Mock utilization based on time + small jitter
    final utilization = (timeProgress * 0.95 + 0.05).clamp(0.0, 1.0);
    final utilizationPercent = (utilization * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x0A191C1E), blurRadius: 32, offset: Offset(0, 12))
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 📦 THE MAIN INFORMATION BLOCK (Bordered Rectangle)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                    ProjectDetailUI.blockPaddingSides,
                    ProjectDetailUI.blockPaddingTop,
                    ProjectDetailUI.blockPaddingSides,
                    ProjectDetailUI.blockPaddingBottom),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: DFColors.primaryStitch.withValues(alpha: 0.8),
                      width: ProjectDetailUI.blockBorderWidth),
                  borderRadius:
                      BorderRadius.circular(ProjectDetailUI.blockBorderRadius),
                ),
                child: Column(
                  children: [
                    // ROW 1: Project Subtitle & Location
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('SITE OVERVIEW',
                            style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.primaryStitch,
                                fontWeight: FontWeight.w900,
                                fontSize: 10)),
                        const SizedBox(width: 8),
                        Text('location.',
                            style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.textSecondary,
                                fontWeight: ProjectDetailUI.matTitleWeight,
                                fontSize: ProjectDetailUI.matTitleFontSize)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // ROW 2: Project Name & Location text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            project.name,
                            style: DFTextStyles.screenTitle.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: DFColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          project.location,
                          style: DFTextStyles.body.copyWith(
                              fontSize: 12, 
                              color: DFColors.textSecondary,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ProjectDetailUI.headerDateTopGap),
              // 📅 DATE RANGE (Bottom Right Corner, Outside Border)
              Text(
                  '${dateFormat.format(project.startDate)} – ${dateFormat.format(project.startDate.add(Duration(days: project.durationDays > 0 ? project.durationDays : 90)))}',
                  style: DFTextStyles.body.copyWith(
                      fontSize: ProjectDetailUI.headerDateFontSize,
                      color: ProjectDetailUI.headerDateColor,
                      fontWeight: ProjectDetailUI.headerDateWeight)),
            ],
          ),

          // 📈 MINIMALISTIC PROGRESS BADGE (Sitting on the Header Border)
          Positioned(
            top: ProjectDetailUI.badgeTopOffset,
            left: ProjectDetailUI.badgeLeftOffset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                    color: DFColors.primaryStitch.withValues(alpha: 0.8),
                    width: ProjectDetailUI.blockBorderWidth),
                borderRadius:
                    BorderRadius.circular(ProjectDetailUI.badgeRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: ProjectDetailUI.badgeRingSize,
                    height: ProjectDetailUI.badgeRingSize,
                    child: CircularProgressIndicator(
                      value: timeProgress,
                      strokeWidth: ProjectDetailUI.badgeRingWidth,
                      backgroundColor:
                          DFColors.primaryStitch.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          DFColors.primaryStitch),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('progress',
                              style: DFTextStyles.labelSm.copyWith(
                                  fontSize: 10, color: DFColors.textSecondary)),
                          const SizedBox(width: 4),
                          Text('${(timeProgress * 100).toInt()}%',
                              style: DFTextStyles.labelSm.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: DFColors.primaryStitch)),
                        ],
                      ),
                      Text('Day $currentDay of $totalDays',
                          style: DFTextStyles.caption.copyWith(
                              fontSize: 8, color: DFColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String title) {
    bool isActive = _activeTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ProjectDetailUI.tabItemHorizontalPadding,
            vertical: ProjectDetailUI.tabItemVerticalPadding),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: isActive ? DFColors.primaryStitch : Colors.transparent,
                  width: ProjectDetailUI.tabIndicatorWeight)),
        ),
        child: Text(title,
            style: DFTextStyles.body.copyWith(
              color: isActive ? DFColors.primaryStitch : DFColors.textSecondary,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            )),
      ),
    );
  }

  Widget _buildOverviewTab(ProjectModel project, EstimateModel? latestEstimate, Map<String, dynamic>? deviation) {
    final totalDays = project.durationDays > 0 
        ? project.durationDays 
        : project.expectedEndDate.difference(project.startDate).inDays;
    
    final now = DateTime.now();
    final start = project.startDate;
    final elapsedDays = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
        
    final timeProgress = (elapsedDays / (totalDays > 0 ? totalDays : 365)).clamp(0.0, 1.0);
    final dateFormat = DateFormat('MMM d, yyyy');

    Map<String, dynamic> matValues = {
      'cement': '0',
      'bricks': '0',
      'steel': '0',
    };

    if (latestEstimate != null) {
      latestEstimate.estimatedMaterials.forEach((key, val) {
        if (key.toLowerCase().contains('cement'))
          matValues['cement'] = val['quantity'].toString();
        if (key.toLowerCase().contains('brick'))
          matValues['bricks'] = val['quantity'].toString();
        if (key.toLowerCase().contains('steel'))
          matValues['steel'] = val['quantity'].toString();
      });
    }

    final teamPreview = project.teamMembers.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProjectHeader(project, deviation),
        const SizedBox(height: 24),
        if (project.status != ProjectStatus.active)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: project.status == ProjectStatus.completed 
                  ? DFColors.success.withValues(alpha: 0.1) 
                  : (project.status == ProjectStatus.closed ? DFColors.critical.withValues(alpha: 0.1) : DFColors.warning.withValues(alpha: 0.1)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: project.status == ProjectStatus.completed 
                    ? DFColors.success 
                    : (project.status == ProjectStatus.closed ? DFColors.critical : DFColors.warning), 
                  width: 1
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    project.status == ProjectStatus.completed 
                      ? Icons.check_circle_rounded 
                      : (project.status == ProjectStatus.closed ? Icons.lock_rounded : Icons.info_outline_rounded), 
                    color: project.status == ProjectStatus.completed 
                      ? DFColors.success 
                      : (project.status == ProjectStatus.closed ? DFColors.critical : DFColors.warning), 
                    size: 24
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      project.status == ProjectStatus.completed 
                        ? 'This project is completed.' 
                        : (project.status == ProjectStatus.closed ? 'This project is closed and read-only.' : 
                           (project.status == ProjectStatus.planning ? 'This project is in planning phase.' : 'This project is currently on hold.')),
                      style: DFTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: project.status == ProjectStatus.completed 
                          ? DFColors.success 
                          : (project.status == ProjectStatus.closed ? DFColors.critical : DFColors.warning), 
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        
        _buildSectionTitle('Financial Summary'),
        const SizedBox(height: 4),
        _buildBudgetSummaryCard(project),
        const SizedBox(height: 24),

        _buildSectionTitle('Project Timeline'),
        const SizedBox(height: 4), // Tighter gap for that 4px look
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4), // Align with title
          child: Column(
            children: [
              // 1. Sliding "TODAY" label above the bar
              SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (MediaQuery.of(context).size.width - 56) * timeProgress,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0), // Center the label on the dot
                        child: Text('TODAY',
                            style: DFTextStyles.labelSm.copyWith(
                                color: ProjectDetailUI.timelineTodayColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // 2. The Slider Bar
              Container(
                width: double.infinity,
                height: ProjectDetailUI.timelineBarHeight,
                margin: const EdgeInsets.only(bottom: 12), // Tighter margin
                decoration: BoxDecoration(
                    color: DFColors.outlineVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(
                        ProjectDetailUI.timelineBarRadius)),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: timeProgress,
                      child: Container(
                          decoration: BoxDecoration(
                              color: DFColors.primaryStitch,
                              borderRadius: BorderRadius.circular(
                                  ProjectDetailUI.timelineBarRadius))),
                    ),
                    Positioned(
                        top: ProjectDetailUI.timelineDotTopOffset,
                        left: 0,
                        child: _buildTimelineDot(active: true)),
                    Positioned(
                        top: ProjectDetailUI.timelineDotTopOffset,
                        left: (MediaQuery.of(context).size.width - 56) *
                            timeProgress,
                        child: _buildTimelineDot(active: true, hasRing: true)),
                    Positioned(
                        top: ProjectDetailUI.timelineDotTopOffset,
                        right: 0,
                        child: _buildTimelineDot(active: false)),
                  ],
                ),
              ),
              // 3. Start and End Dates below the bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateFormat.format(project.startDate),
                    style: DFTextStyles.labelSm.copyWith(
                        fontSize: ProjectDetailUI.timelineDateFontSize,
                        fontWeight: ProjectDetailUI.timelineDateWeight,
                        letterSpacing:
                            ProjectDetailUI.timelineDateLetterSpacing),
                  ),
                  Text(
                    dateFormat.format(project.startDate.add(Duration(days: project.durationDays > 0 ? project.durationDays : 90))),
                    style: DFTextStyles.labelSm.copyWith(
                        fontSize: ProjectDetailUI.timelineDateFontSize,
                        fontWeight: ProjectDetailUI.timelineDateWeight,
                        letterSpacing:
                            ProjectDetailUI.timelineDateLetterSpacing),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24), // Reduced gap before next section

        _buildSectionTitle('Material Estimations'),
        const SizedBox(height: 4), 
        Consumer(
          builder: (context, ref, _) {
            final logs = ref.watch(projectLogsProvider(project.id)).value ?? [];
            
            return Column(
              children: [
                _buildMaterialPillRow('Total Cement', matValues['cement'], 'Bags', logs, latestEstimate),
                const SizedBox(height: 8),
                _buildMaterialPillRow('Total Bricks', matValues['bricks'], 'Nos', logs, latestEstimate),
                const SizedBox(height: 8),
                _buildMaterialPillRow('Total Steel', matValues['steel'], 'Kg', logs, latestEstimate),
              ],
            );
          },
        ),

        SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('On-Site Team'),
            Consumer(
              builder: (context, ref, _) {
                final userRole = ref.watch(userProfileProvider).value?.role;
                if (userRole == UserRole.manager ||
                    userRole == UserRole.admin) {
                  return Transform.translate(
                    offset: const Offset(2, -12), // True superscript height
                    child: TextButton(
                      onPressed: () =>
                          context.push('/projects/${widget.projectId}/team'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      child: Text('manage team.',
                          style: DFTextStyles.labelSm.copyWith(
                            color: DFColors.primaryStitch,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          )),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        const SizedBox(
            height:
                2), // Small gap for a compact but readable label-table spacing
        Container(
          width: double.infinity,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(
              top: BorderSide(
                color: DFColors.outline.withValues(alpha: 0.5),
                width: 1.0,
              ),
              bottom: BorderSide(
                color: DFColors.outline.withValues(alpha: 0.5),
                width: 1.0,
              ),
              left: BorderSide(
                color: DFColors.outline.withValues(alpha: 0.5),
                width: 1.0,
              ),
              right: BorderSide(
                color: DFColors.outline.withValues(alpha: 0.5),
                width: 1.0,
              ),
              horizontalInside: BorderSide(
                color: DFColors.outline.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.0),
            },
            children: List.generate(teamPreview.length, (index) {
              final uid = teamPreview[index];
              return TableRow(
                children: [
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final userAsync = ref.watch(userByIdProvider(uid));
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          child: userAsync.when(
                            data: (user) => Text(
                              user?.name ?? 'Unknown Staff',
                              style: DFTextStyles.body.copyWith(
                                fontSize:
                                    ProjectDetailUI.teamMemberNameFontSize,
                                fontWeight:
                                    ProjectDetailUI.teamMemberNameWeight,
                              ),
                            ),
                            loading: () => Container(
                                width: 40, height: 10, color: Colors.grey[100]),
                            error: (_, __) => const Text('Error',
                                style: TextStyle(fontSize: 10)),
                          ),
                        );
                      },
                    ),
                  ),
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final userAsync = ref.watch(userByIdProvider(uid));
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          child: userAsync.when(
                            data: (user) => Text(
                              user?.designation ??
                                  (user?.role == UserRole.manager
                                      ? 'Project Manager'
                                      : 'Site Engineer'),
                              style: DFTextStyles.caption.copyWith(
                                fontSize:
                                    ProjectDetailUI.teamMemberRoleFontSize,
                                color: DFColors.textSecondary,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        if (project.teamMembers.length > 4)
          Padding(
            padding: const EdgeInsets.only(
                top: 2.0), // Tightened gap for compact layout
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('+${project.teamMembers.length - 4} more',
                    style: DFTextStyles.caption
                        .copyWith(fontStyle: FontStyle.italic, fontSize: 10)),
              ],
            ),
          ),


        const SizedBox(height: 32),
        
        // REPORT GENERATION BUTTON
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _generateProjectReport,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: const Text('GENERATE ANALYSIS REPORT'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DFColors.primaryStitch,
              side: const BorderSide(color: DFColors.primaryStitch, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildBudgetSummaryCard(ProjectModel project) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    final materialCost = ref.watch(estimatedCostProvider(project.projectId));
    final contractorEstimate = materialCost * 1.5;
    final totalProjectEstimate = materialCost * 2.5;
    final invoicedTotal = ref.watch(invoicedTotalProvider(project.projectId));
    
    final isOverBudget = invoicedTotal > totalProjectEstimate && totalProjectEstimate > 0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSimpleFinanceCard(
                'CAD MATERIALS', 
                currencyFormat.format(materialCost), 
                Icons.architecture, 
                DFColors.textSecondary
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSimpleFinanceCard(
                'CONTRACTOR ESTIMATE', 
                currencyFormat.format(contractorEstimate), 
                Icons.engineering_outlined, 
                DFColors.textSecondary,
                sublabel: 'Labour + overhead + profit',
                onInfoTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Contractor Estimate'),
                      content: const Text('This includes Labour & Workmanship and Management & Service Fees based on standard construction benchmarks.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('GOT IT'))],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSimpleFinanceCard(
                'TOTAL PROJECT EST.', 
                currencyFormat.format(totalProjectEstimate), 
                Icons.analytics_outlined, 
                DFColors.primaryStitch
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSimpleFinanceCard(
                'TOTAL INVOICED', 
                currencyFormat.format(invoicedTotal), 
                Icons.receipt_long, 
                isOverBudget ? DFColors.critical : DFColors.success
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSimpleFinanceCard(String label, String value, IconData icon, Color color, {String? sublabel, VoidCallback? onInfoTap}) {
    return DFCard(
      padding: const EdgeInsets.all(16),
      color: DFColors.surfaceContainerLow.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: DFTextStyles.labelSm.copyWith(color: color, fontSize: 10), overflow: TextOverflow.ellipsis)),
              if (onInfoTap != null)
                GestureDetector(
                  onTap: onInfoTap,
                  child: Icon(Icons.info_outline, size: 12, color: color.withOpacity(0.6)),
                ),
            ],
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sublabel, style: DFTextStyles.caption.copyWith(fontSize: 8, color: color.withOpacity(0.7))),
            ),
          const SizedBox(height: 8),
          Text(value, style: DFTextStyles.metricLarge.copyWith(fontSize: 18, color: DFColors.primaryStitch)),
        ],
      ),
    );
  }

  Widget _buildBillsTab(ProjectModel project) {
    return Consumer(
      builder: (context, ref, _) {
        final billsAsync = ref.watch(projectBillsProvider(project.projectId));

        return billsAsync.when(
          data: (bills) {
            double totalSpent = bills.fold(0, (sum, b) => sum + b.amount);
            final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Financial Overview'),
                const SizedBox(height: 16),
                DFCard(
                  padding: const EdgeInsets.all(20),
                  color: DFColors.primaryStitch.withValues(alpha: 0.05),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CUMULATIVE SPEND',
                                style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontSize: 10)),
                            Text(currencyFormat.format(totalSpent),
                                style: DFTextStyles.metricLarge.copyWith(fontSize: 24, color: DFColors.primaryStitch)),
                          ],
                        ),
                      ),
                      CircularProgressIndicator(
                        value: project.plannedBudget > 0 ? totalSpent / project.plannedBudget : 0,
                        backgroundColor: DFColors.outlineVariant.withValues(alpha: 0.2),
                        color: totalSpent > project.plannedBudget ? DFColors.critical : DFColors.primaryStitch,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildMaterialsReceivedSummary(project),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionTitle('Invoice Ledger'),
                    if ((project.status == ProjectStatus.active || project.status == ProjectStatus.planning) && project.status != ProjectStatus.closed)
                      TextButton.icon(
                        onPressed: () => context.push('/projects/${project.projectId}/bills/upload'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Bill'),
                        style: TextButton.styleFrom(foregroundColor: DFColors.primaryStitch),
                      ),
                  ],
                ),
                if (bills.isEmpty)
                  _buildEmptyBillsState(project)
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final bill = bills[index];
                      return _buildBillLedgerItem(bill);
                    },
                  ),
                const SizedBox(height: 40),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
          error: (e, _) => Center(child: Text('Error loading bills: $e')),
        );
      },
    );
  }

  Widget _buildMaterialsReceivedSummary(ProjectModel project) {
    final receivedData = ref.watch(materialsReceivedProvider(project.projectId));
    if (receivedData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Materials Received to Date'),
        const SizedBox(height: 16),
        DFCard(
          padding: const EdgeInsets.all(16),
          color: DFColors.surfaceContainerLow.withValues(alpha: 0.3),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: receivedData.entries.map((e) {
              return Container(
                constraints: const BoxConstraints(minWidth: 100),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: DFColors.primaryStitch.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DFColors.primaryStitch.withValues(alpha: 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key.toUpperCase(), style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text('${e.value.toStringAsFixed(0)} units', style: DFTextStyles.metricLarge.copyWith(fontSize: 16, color: DFColors.primaryStitch)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEmptyBillsState(ProjectModel project) {
    return DFCard(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: DFColors.outlineVariant),
          const SizedBox(height: 16),
          Text('No Invoices Found', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Upload bills to track cumulative project expenditure and verify against CAD estimates.',
              textAlign: TextAlign.center, style: DFTextStyles.caption),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/projects/${project.projectId}/bills/upload'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('UPLOAD FIRST INVOICE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DFColors.primaryStitch,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillLedgerItem(VendorBillModel bill) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    final dateFormat = DateFormat('dd MMM, yyyy');

    return DFCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        // Show bill details / items
        _showBillDetails(bill);
      },
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DFColors.outlineVariant.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_getCategoryIcon(bill.category), color: DFColors.primaryStitch, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bill.vendorName,
                    style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                Text('${bill.category} • ${dateFormat.format(bill.date)}', style: DFTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(currencyFormat.format(bill.amount),
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w900, color: DFColors.primaryStitch)),
              if (bill.items.isNotEmpty)
                Text('${bill.items.length} items', style: DFTextStyles.caption.copyWith(fontSize: 10)),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: DFColors.outlineVariant, size: 20),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'cement': return Icons.layers_outlined;
      case 'steel/rebar': return Icons.grid_3x3_rounded;
      case 'sand/aggregate': return Icons.grain;
      case 'bricks/blocks': return Icons.foundation;
      case 'equipment rent': return Icons.construction;
      case 'labor payment': return Icons.groups_outlined;
      default: return Icons.receipt_long_outlined;
    }
  }

  void _showBillDetails(VendorBillModel bill) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Invoice Details', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VENDOR', style: DFTextStyles.labelSm),
                    Text(bill.vendorName, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TOTAL AMOUNT', style: DFTextStyles.labelSm),
                    Text(currencyFormat.format(bill.amount),
                        style: DFTextStyles.metricLarge.copyWith(fontSize: 20, color: DFColors.primaryStitch)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('LINE ITEMS', style: DFTextStyles.labelSm),
            const SizedBox(height: 8),
            if (bill.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No itemized breakdown available.', style: DFTextStyles.caption)),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: bill.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final item = bill.items[index];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.description, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                              Text('${item.quantity} ${item.unit} @ ₹${item.rate}', style: DFTextStyles.caption),
                            ],
                          ),
                        ),
                        Text(currencyFormat.format(item.amount), style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    );
                  },
                ),
              ),
            // View Original Invoice button removed as Storage is disabled
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineDot({required bool active, bool hasRing = false}) {
    return Container(
      width: ProjectDetailUI.timelineDotSize,
      height: ProjectDetailUI.timelineDotSize,
      decoration: BoxDecoration(
        color: active ? DFColors.primaryStitch : DFColors.outlineVariant,
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white, width: ProjectDetailUI.timelineDotBorderWidth),
        boxShadow: hasRing
            ? [
                BoxShadow(
                    color: DFColors.primaryStitch.withValues(alpha: 0.2),
                    spreadRadius: 4)
              ]
            : null,
      ),
    );
  }

  Widget _buildMaterialPillRow(String title, String value, String unit, List<ResourceLogModel> logs, EstimateModel? estimate) {
    final materialKey = title.split(' ').last.toLowerCase();
    double estimatedQty = 0;
    
    if (estimate != null) {
      estimate.estimatedMaterials.forEach((key, val) {
        if (key.toLowerCase().contains(materialKey)) {
          estimatedQty = (val['quantity'] as num? ?? 0).toDouble();
        }
      });
    }

    final statusData = _materialStatus(materialKey, estimatedQty, logs);
    
    return _buildMaterialEstimationCard(
      title, 
      value, 
      unit, 
      statusData['label'] as String, 
      statusData['color'] as Color
    );
  }

  Map<String, dynamic> _materialStatus(String material, double estimatedQty, List<ResourceLogModel> logs) {
    if (logs.isEmpty || estimatedQty == 0) {
      return {'label': 'TRACKING', 'color': DFColors.outline};
    }

    double consumed = 0;
    for (final log in logs) {
      final mats = log.materials;
      // Try to find the material in the log
      mats.forEach((key, val) {
        if (key.toLowerCase().contains(material)) {
          consumed += (val as num? ?? 0).toDouble();
        }
      });
    }

    if (consumed == 0) return {'label': 'TRACKING', 'color': DFColors.outline};

    final ratio = consumed / estimatedQty;

    if (ratio < 0.5) return {'label': 'STABLE', 'color': const Color(0xFF16A34A)};
    if (ratio < 0.85) return {'label': 'NORMAL', 'color': const Color(0xFF2563EB)};
    if (ratio < 1.0) return {'label': 'HIGH USAGE', 'color': const Color(0xFFDC2626)};
    return {'label': 'OVER ESTIMATED', 'color': const Color(0xFFDC2626)};
  }

  Widget _buildMaterialEstimationCard(String title, String value, String unit,
      String statusLabel, Color statusColor) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: ProjectDetailUI.matCardIndent),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: ProjectDetailUI.matCardWidthFactor,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The Main Card Block
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: ProjectDetailUI.matCardPadding,
                    vertical: ProjectDetailUI.matCardPaddingVertical),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ProjectDetailUI.matCardRadius),
                    border: Border.all(
                        color: DFColors.outlineVariant.withValues(
                            alpha: ProjectDetailUI.matCardBorderOpacity))),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start, // Internal text left
                  children: [
                    Text(title.toUpperCase(),
                        style: DFTextStyles.labelSm.copyWith(
                            fontSize: ProjectDetailUI.matTitleFontSize,
                            fontWeight: ProjectDetailUI.matTitleWeight,
                            letterSpacing:
                                ProjectDetailUI.matTitleLetterSpacing)),
                    const SizedBox(height: ProjectDetailUI.matValueTopGap),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.start, // Numbers left
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(value,
                            style: DFTextStyles.screenTitle.copyWith(
                                fontSize: ProjectDetailUI.matValueFontSize,
                                height: 1.0)),
                        const SizedBox(width: 4),
                        Text(unit,
                            style: DFTextStyles.body.copyWith(
                                color: DFColors.textSecondary,
                                fontSize: ProjectDetailUI.matUnitFontSize)),
                      ],
                    ),
                  ],
                ),
              ),
              // The Status Badge
              Positioned(
                top: -10,
                right: ProjectDetailUI.matCardPadding,
                child: GestureDetector(
                  onTap: () => setState(() => _activeTabIndex = 2),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: ProjectDetailUI.matStatusCircleSize,
                          height: ProjectDetailUI.matStatusCircleSize,
                          decoration: BoxDecoration(
                              color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(
                            width: ProjectDetailUI.matStatusOutsideGap),
                        Text(statusLabel.toUpperCase(),
                            style: DFTextStyles.labelSm.copyWith(
                              fontSize: ProjectDetailUI.matStatusFontSize,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildEstimatesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final estimateAsync = ref.watch(latestEstimateProvider(widget.projectId));
        
        final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
        
        return estimateAsync.when(
          data: (estimate) {
            final project = projectAsync.valueOrNull;
            if (estimate == null) {
              return _buildPlaceholderEstimates('No estimates found. Upload a CAD drawing to begin.');
            }
            
            final mats = estimate.estimatedMaterials;
            final geo = estimate.geometryData;
            final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
            
            double grandTotal = 0;
            mats.forEach((name, data) {
              if (name == 'metadata') return;
              final qty = (data['quantity'] as num).toDouble();
              grandTotal += MaterialRates.calculateEstimatedCost(name, qty);
            });
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Estimation Intelligence'),
                const SizedBox(height: 16),
                
                // Geometry Badge Row
                Row(
                  children: [
                    _buildMetricChip(Icons.square_foot, 'Floor', '${geo['totalFloorArea']?.toStringAsFixed(1) ?? "0"} m²'),
                    const SizedBox(width: 12),
                    _buildMetricChip(Icons.straighten, 'Wall', '${geo['totalWallLength']?.toStringAsFixed(1) ?? "0"} m'),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Breakdown Chart & List
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 180,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 40,
                            sections: [
                              _buildPieSection(mats['cement']?['quantity'] ?? 0, 'Cement', DFColors.primaryStitch),
                              _buildPieSection((mats['bricks']?['quantity'] ?? 0) / 100, 'Bricks', Colors.orange),
                              _buildPieSection((mats['steel']?['quantity'] ?? 0) / 10, 'Steel', Colors.red),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildEstimationHeader(),
                      const Divider(height: 16, color: DFColors.outlineVariant),
                      ...mats.entries.where((e) => e.key != 'metadata').map((entry) {
                        final name = entry.key;
                        final data = entry.value;
                        final qty = (data['quantity'] as num).toDouble();
                        
                        final effectiveQty = MaterialRates.getQuantityInRateUnit(name, qty);
                        final rateUnit = MaterialRates.getRateUnitForMaterial(name);
                        final rate = MaterialRates.getRateForMaterial(name);
                        final total = MaterialRates.calculateEstimatedCost(name, qty);
                        
                        return Column(
                          children: [
                            _buildMaterialEstimationRow(
                              name.capitalize(), 
                              '${effectiveQty.toStringAsFixed(1)} $rateUnit', 
                              rate > 0 ? '₹$rate/$rateUnit' : 'N/A',
                              total > 0 ? '₹${NumberFormat('#,##,###').format(total)}' : '--',
                            ),
                            const Divider(height: 16, color: DFColors.outlineVariant),
                          ],
                        );
                      }).toList(),
                      
                      const SizedBox(height: 8),
                      _buildTotalEstimationRow(mats),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                _buildSectionTitle('Contractor Estimate Breakdown'),
                const SizedBox(height: 4),
                DFCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildBreakdownRow('Labour & Workmanship', (grandTotal * 2.5) * 0.4, currencyFormat),
                      const Divider(height: 20),
                      _buildBreakdownRow('Management & Service Fee', (grandTotal * 2.5) * 0.2, currencyFormat),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                _buildDisclaimerCard(),
                
                const SizedBox(height: 24),
                
                // Action Row
                if (project?.status != ProjectStatus.closed)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/projects/${widget.projectId}/cad-upload'),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('UPDATE CAD DRAWING'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DFColors.primaryStitch,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
          error: (e, _) => Center(child: Text('Error: $e')),
        );
      },
    );
  }

  PieChartSectionData _buildPieSection(num value, String title, Color color) {
    return PieChartSectionData(
      color: color,
      value: value.toDouble(),
      title: '',
      radius: 50,
      showTitle: false,
    );
  }

  Widget _buildMetricChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DFColors.primaryStitch.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.primaryStitch.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: DFColors.primaryStitch),
          const SizedBox(width: 8),
          Text('$label: $value', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
        ],
      ),
    );
  }

  Widget _buildEstimationHeader() {
    return Row(
      children: [
        Expanded(flex: 2, child: Text('RESOURCE', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary))),
        Expanded(flex: 2, child: Text('QUANTITY', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary))),
        Expanded(flex: 2, child: Text('RATE', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary))),
        Expanded(flex: 2, child: Text('EST. COST', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary), textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buildMaterialEstimationRow(String name, String qty, String rate, String cost) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(name, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13))),
        Expanded(flex: 2, child: Text(qty, style: DFTextStyles.body.copyWith(fontSize: 12))),
        Expanded(flex: 2, child: Text(rate, style: DFTextStyles.body.copyWith(fontSize: 12, color: DFColors.textSecondary))),
        Expanded(flex: 2, child: Text(cost, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w900, color: DFColors.primaryStitch, fontSize: 13), textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buildTotalEstimationRow(Map<String, dynamic> mats) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    double grandTotal = 0;
    mats.forEach((name, data) {
      if (name == 'metadata') return;
      final qty = (data['quantity'] as num).toDouble();
      grandTotal += MaterialRates.calculateEstimatedCost(name, qty);
    });

    final contractorShare = grandTotal * 1.5;
    final totalProjectEstimate = grandTotal * 2.5;

    return Column(
      children: [
        _buildSummaryLine('Material Cost (CAD)', grandTotal, currencyFormat),
        _buildSummaryLine('Contractor Estimate', contractorShare, currencyFormat),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('TOTAL PROJECT ESTIMATE', 
                style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w900, color: DFColors.primaryStitch),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('₹${NumberFormat('#,##,###').format(totalProjectEstimate)}', 
              style: DFTextStyles.metricLarge.copyWith(fontSize: 18, color: DFColors.primaryStitch)),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryLine(String label, double amount, NumberFormat format) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, 
              style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(format.format(amount), style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, double amount, NumberFormat format) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, 
            style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(format.format(amount), style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w900, color: DFColors.primaryStitch)),
      ],
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DFColors.outlineVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: DFColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cost estimates vary based on site location, local vendor rates, and construction wastage. ConstructIQ defaults are based on standard CPWD benchmarks 2024.',
              style: DFTextStyles.caption.copyWith(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPlaceholderEstimates(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Estimates Management'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: DFColors.primaryContainerStitch.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.analytics_outlined, size: 48, color: DFColors.primaryContainerStitch),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: DFTextStyles.caption),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/projects/${widget.projectId}/cad-upload'),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('UPLOAD CAD DRAWING'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DFColors.primaryStitch,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviationsTab(
      ProjectModel? project, Map<String, dynamic>? devData) {
    if (project == null)
      return const Center(child: CircularProgressIndicator());

    // On-device ML Prediction Logic
    final mlInput = OverrunPredictionInput(
      materialDeviationAvg:
          getMaterialDeviationAvg(devData?['deviations'] ?? {}),
      equipmentIdleRatio: 0.10, // Assuming 10% idle as baseline
      daysElapsedPct:
          calculateDaysElapsedPct(project.startDate, project.expectedEndDate),
      budgetSize: project.plannedBudget / 100000.0, // lakh units
      projectTypeEncoded: encodeProjectType(project.projectType),
    );

    if (devData == null || devData['overallSeverity'] == 'normal') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Deviations'),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
                color: DFColors.surfaceContainerLow.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: DFColors.outlineVariant.withValues(alpha: 0.1))),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                      color: DFColors.surfaceContainerHighest,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.query_stats_outlined,
                      size: 32, color: DFColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text('Tracking Not Started',
                    style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                    'Upload your first invoice to begin monitoring deviations between CAD estimates and actual on-site consumption.',
                    textAlign: TextAlign.center,
                    style: DFTextStyles.body
                        .copyWith(fontSize: 14, color: DFColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }

    final severity = devData['overallSeverity'] as String;
    final reason =
        devData['reason'] ?? 'Unusual resource consumption patterns detected.';
    final insight =
        devData['aiInsight'] ?? 'Monitor site logs for the next 48 hours.';
    Color color = severity == 'critical'
        ? const Color(0xFFB10010)
        : const Color(0xFFFEA619);

    return Consumer(
      builder: (context, ref, child) {
        final predictionAsync = ref.watch(onDeviceOverrunProvider(mlInput));

        final prediction = predictionAsync.asData?.value;
        final isOnDevice = prediction?['on_device'] == true;
        final prob = (prediction?['probability'] as double? ??
                (devData['mlOverrunProbability'] as num? ?? 0.0).toDouble()) *
            100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Active Deviation'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: color, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(severity.toUpperCase(),
                                  style: DFTextStyles.labelSm.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                      fontSize: 12)),
                            ),
                            if (isOnDevice)
                              Positioned(
                                right: -2,
                                top: 0,
                                child: Text('On-device Prediction',
                                    style: DFTextStyles.caption.copyWith(
                                        color: DFColors.normal,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500)),
                              ),
                          ],
                        ),
                      ),
                      if (predictionAsync.isLoading)
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5))
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(reason,
                      style: DFTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(insight,
                      style: DFTextStyles.body.copyWith(
                          color: DFColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: DFColors.textSecondary.withValues(
                                  alpha: 0.4),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Overrun Risk',
                            style: DFTextStyles.labelSm
                                .copyWith(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Text('${prob.toInt()}%',
                          style: DFTextStyles.screenTitle
                              .copyWith(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: prob / 100,
                      backgroundColor: DFColors.surfaceContainerHighest,
                      color: color,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAiChatTab(ProjectModel project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('AI Project Assistant'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: DFColors.primaryStitch,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x4D003E7E),
                          blurRadius: 16,
                          offset: Offset(0, 8))
                    ]),
                child: const Icon(Icons.smart_toy_outlined,
                    size: 32, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text('Context: ${project.name}',
                  style: DFTextStyles.body
                      .copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                  'Ask questions about project deviations, budget utilization, or material requirements. I analyze your CAD estimates and site logs to provide insights.',
                  textAlign: TextAlign.center,
                  style: DFTextStyles.body
                      .copyWith(fontSize: 14, color: DFColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildChatPrompt('Explain recent cement spikes?', Icons.query_stats),
        const SizedBox(height: 12),
        _buildChatPrompt(
            "Compare logs with CAD estimates", Icons.inventory_2_outlined),
      ],
    );
  }

  Widget _buildChatPrompt(String text, IconData icon) {
    return InkWell(
      onTap: () => context.push('/projects/${widget.projectId}/ai-chat'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
                color: DFColors.outlineVariant.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: DFColors.primaryStitch),
            const SizedBox(width: 12),
            Text(text,
                style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: ProjectDetailUI.sectionTitleBottomPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: ProjectDetailUI.sectionBulletSize,
            height: ProjectDetailUI.sectionBulletSize,
            decoration: const BoxDecoration(
                color: ProjectDetailUI.sectionTitleColor,
                shape: BoxShape.circle),
          ),
          SizedBox(width: ProjectDetailUI.sectionBulletGap),
          Text(title,
              style: DFTextStyles.body.copyWith(
                  fontWeight: ProjectDetailUI.sectionTitleWeight,
                  fontSize: ProjectDetailUI.sectionTitleFontSize,
                  color: ProjectDetailUI.sectionTitleColor)),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(
      BuildContext context, WidgetRef ref) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: DFColors.critical),
              const SizedBox(width: 12),
              const Text('Delete Project'),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete this project?',
                    style: DFTextStyles.body
                        .copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    'This action will permanently remove all estimates, documents and logs associated with this project. This cannot be undone.',
                    style: DFTextStyles.caption
                        .copyWith(color: DFColors.textSecondary)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('CANCEL',
                  style: DFTextStyles.labelSm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: DFColors.textSecondary)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: DFColors.critical,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('DELETE'),
              onPressed: () async {
                try {
                  // Show loading
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                        content: Text('Deleting project...'),
                        behavior: SnackBarBehavior.floating),
                  );

                  await ref
                      .read(projectServiceProvider)
                      .deleteProject(widget.projectId);

                  if (this.context.mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                          content: Text('Project deleted successfully'),
                          backgroundColor: DFColors.normal,
                          behavior: SnackBarBehavior.floating),
                    );
                    this.context.go('/dashboard');
                  }
                } catch (e) {
                  if (this.context.mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: DFColors.critical,
                          behavior: SnackBarBehavior.floating),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showCloseConfirmation(BuildContext context, WidgetRef ref, ProjectModel project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Project?'),
        content: const Text(
            'This will make the project read-only. No further invoices or logs can be added. This action cannot be easily undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              try {
                final closedProject = project.copyWith(status: ProjectStatus.closed);
                await ref.read(projectServiceProvider).updateProject(closedProject);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Project closed successfully.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error closing project: $e')),
                  );
                }
              }
            },
            child: const Text('CLOSE PROJECT', style: TextStyle(color: DFColors.critical)),
          ),
        ],
      ),
    );
  }
}
