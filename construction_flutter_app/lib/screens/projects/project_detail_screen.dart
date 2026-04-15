import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Budget updated successfully from invoice!'),
          backgroundColor: DFColors.success,
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Extraction failed: $e')));
      } finally {
        if (mounted) setState(() => _isUploadingInvoice = false);
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
                      _buildProjectHeader(
                          project, deviationAsync.asData?.value),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, ProjectDetailUI.screenTopPadding, 24, 150), 
                        child: _activeTabIndex == 0 ? _buildOverviewTab(project, estimateAsync.asData?.value) :
                               _activeTabIndex == 1 ? _buildEstimatesTab() :
                               _activeTabIndex == 2 ? _buildDeviationsTab(project, deviationAsync.asData?.value) :
                               _buildAiChatTab(project),
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () =>
                    context.push('/projects/${widget.projectId}/log-entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DFColors.primaryStitch,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 8,
                  shadowColor: DFColors.primaryStitch.withValues(alpha: 0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_task_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Log Entry',
                        style: DFTextStyles.body.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
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
      ),
    );
  }

  Widget _buildProjectHeader(
      ProjectModel project, Map<String, dynamic>? latestDev) {
    final currencyFormat =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    final dateFormat = DateFormat('MMM yyyy');

    // Calculate progress based on time
    final totalDays =
        project.expectedEndDate.difference(project.startDate).inDays;
    final elapsedDays = DateTime.now().difference(project.startDate).inDays;
    final timeProgress = (elapsedDays / totalDays).clamp(0.0, 1.0);

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
                    // ROW 1: Status & Budget Label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('active.',
                            style: DFTextStyles.labelSm.copyWith(
                                color: const Color(0xFF16A34A),
                                fontWeight: FontWeight.w900,
                                fontSize: ProjectDetailUI.matStatusFontSize)),
                        const SizedBox(width: 8),
                        Text('total budget.',
                            style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.textSecondary,
                                fontWeight: ProjectDetailUI.matTitleWeight,
                                fontSize: ProjectDetailUI.matTitleFontSize)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // ROW 2: Project Name & Budget Amount
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
                          currencyFormat.format(project.plannedBudget), 
                          style: DFTextStyles.screenTitle.copyWith(fontSize: 18, fontWeight: FontWeight.w900, color: DFColors.primaryStitch),
                        ),
                      ],
                    ),
                    if (project.plannedBudget == 0.0) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _isUploadingInvoice 
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : ElevatedButton.icon(
                                onPressed: () => _pickInvoice(project),
                                icon: const Icon(Icons.receipt_long, size: 16),
                                label: const Text('Add Invoice'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: DFColors.primaryStitch,
                                  side: const BorderSide(color: DFColors.primaryStitch),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: ProjectDetailUI.headerDateTopGap),
              // 📅 DATE RANGE (Bottom Right Corner, Outside Border)
              Text(
                  '${dateFormat.format(project.startDate)} – ${dateFormat.format(project.expectedEndDate)}',
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
                      value: utilization,
                      strokeWidth: ProjectDetailUI.badgeRingWidth,
                      backgroundColor:
                          DFColors.primaryStitch.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          DFColors.primaryStitch),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('progress',
                      style: DFTextStyles.labelSm.copyWith(
                          fontSize: 10, color: DFColors.textSecondary)),
                  const SizedBox(width: 4),
                  Text('$utilizationPercent%',
                      style: DFTextStyles.labelSm.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: DFColors.primaryStitch)),
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

  Widget _buildOverviewTab(
      ProjectModel project, EstimateModel? latestEstimate) {
    final totalDays =
        project.expectedEndDate.difference(project.startDate).inDays;
    final elapsedDays = DateTime.now().difference(project.startDate).inDays;
    final timeProgress = (elapsedDays / totalDays).clamp(0.0, 1.0);
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
        _buildSectionTitle('Project Timeline'),
        const SizedBox(height: 4), // Tighter gap for that 4px look
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4), // Align with title
          child: Column(
            children: [
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      dateFormat.format(project.startDate),
                      style: DFTextStyles.labelSm.copyWith(
                          fontSize: ProjectDetailUI.timelineDateFontSize,
                          fontWeight: ProjectDetailUI.timelineDateWeight,
                          letterSpacing:
                              ProjectDetailUI.timelineDateLetterSpacing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text('TODAY',
                        style: DFTextStyles.labelSm.copyWith(
                            color: ProjectDetailUI.timelineTodayColor,
                            fontSize: ProjectDetailUI.timelineDateFontSize,
                            fontWeight: ProjectDetailUI.timelineDateWeight,
                            letterSpacing:
                                ProjectDetailUI.timelineDateLetterSpacing)),
                  ),
                  Expanded(
                    child: Text(
                      dateFormat.format(project.expectedEndDate),
                      style: DFTextStyles.labelSm.copyWith(
                          fontSize: ProjectDetailUI.timelineDateFontSize,
                          fontWeight: ProjectDetailUI.timelineDateWeight,
                          letterSpacing:
                              ProjectDetailUI.timelineDateLetterSpacing),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24), // Reduced gap before next section

        _buildSectionTitle('Material Estimations'),
        const SizedBox(height: 4), // Matched 4px timeline gap
        _buildMaterialEstimationCard('Total Cement', matValues['cement'],
            'Bags', 'Stable', const Color(0xFF16A34A)),
        const SizedBox(height: 8), // Reduced from 12 for compact flow
        _buildMaterialEstimationCard('Total Bricks', matValues['bricks'], 'Nos',
            'Normal', const Color(0xFF2563EB)),
        const SizedBox(height: 8), // Reduced from 12 for compact flow
        _buildMaterialEstimationCard('Total Steel', matValues['steel'], 'Kg',
            'Price High', const Color(0xFFDC2626)),

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

        SizedBox(height: 20),
        _buildSectionTitle('Workforce & Personnel'),
        const SizedBox(height: 2), // Tighter gap
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: ProjectDetailUI.utilCardIndent),
          child: Column(
            children: [
              DFCard(
                onTap: () =>
                    context.push('/projects/${widget.projectId}/workforce'),
                padding: const EdgeInsets.symmetric(
                    horizontal: ProjectDetailUI.utilCardPadding, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined,
                        color: DFColors.primaryStitch,
                        size: ProjectDetailUI.utilIconSize),
                    SizedBox(width: ProjectDetailUI.utilRowIconGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WORKFORCE OVERVIEW',
                              style: DFTextStyles.labelSm.copyWith(
                                  fontSize: ProjectDetailUI.utilTitleFontSize,
                                  fontWeight: ProjectDetailUI.utilTitleWeight)),
                          Text('View trade-wise stats and daily headcounts.',
                              style: DFTextStyles.caption.copyWith(
                                  fontSize: ProjectDetailUI.utilCaptionFontSize,
                                  color: DFColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: DFColors.outlineVariant, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 20),
        _buildSectionTitle('Financial Documents'),
        const SizedBox(height: 2), // Tighter gap
        Consumer(
          builder: (context, ref, _) {
            final userRole = ref.watch(userProfileProvider).value?.role;
            final isAuthorized = userRole == UserRole.engineer ||
                userRole == UserRole.manager ||
                userRole == UserRole.admin;

            return Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ProjectDetailUI.financialCardIndent),
              child: DFCard(
                onTap: isAuthorized
                    ? () => context
                        .push('/projects/${widget.projectId}/bills/upload')
                    : null,
                padding: const EdgeInsets.symmetric(
                    horizontal: ProjectDetailUI.utilCardPadding, vertical: 12),
                color: isAuthorized
                    ? DFColors.primaryStitch.withValues(alpha: 0.05)
                    : Colors.grey[100],
                child: Opacity(
                  opacity: isAuthorized ? 1.0 : 0.5,
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: DFColors.primaryStitch,
                          size: ProjectDetailUI.utilIconSize),
                      SizedBox(width: ProjectDetailUI.utilRowIconGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('UPLOAD VENDOR BILL',
                                style: DFTextStyles.labelSm.copyWith(
                                    fontSize: ProjectDetailUI.utilTitleFontSize,
                                    fontWeight:
                                        ProjectDetailUI.utilTitleWeight)),
                            Text('Archive digital copies of site invoices.',
                                style: DFTextStyles.caption.copyWith(
                                    fontSize:
                                        ProjectDetailUI.utilCaptionFontSize,
                                    color: DFColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.file_upload_outlined,
                          color: DFColors.primaryStitch, size: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamMember(String name, String role, {required bool isOthers}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: DFColors.outlineVariant.withValues(alpha: 0.2))),
      child: Row(
        children: [
          Container(
            width: ProjectDetailUI.teamMemberAvatarSize,
            height: ProjectDetailUI.teamMemberAvatarSize,
            decoration: BoxDecoration(
                color: isOthers
                    ? DFColors.primaryContainerStitch
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(
                    ProjectDetailUI.teamMemberAvatarRadius)),
            child: isOthers
                ? const Center(
                    child: Text('+5',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)))
                : const Icon(Icons.person, color: Colors.white),
          ),
          SizedBox(width: ProjectDetailUI.teamMemberInfoGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name,
                    style: DFTextStyles.body.copyWith(
                        fontSize: ProjectDetailUI.teamMemberNameFontSize,
                        fontWeight: ProjectDetailUI.teamMemberNameWeight),
                    overflow: TextOverflow.ellipsis),
                Text(role,
                    style: DFTextStyles.caption.copyWith(
                        fontSize: ProjectDetailUI.teamMemberRoleFontSize),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimatesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Estimates Management'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: DFColors.primaryContainerStitch.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DFColors.primaryContainerStitch.withValues(alpha: 0.3), width: 2, style: BorderStyle.none),
          ),
          child: Column(
            children: [
              const Icon(Icons.analytics_outlined, size: 48, color: DFColors.primaryContainerStitch),
              const SizedBox(height: 12),
              Text('Estimation Intelligence', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Switch to the Overview tab to see the latest material benchmarks generated for this project.', 
                textAlign: TextAlign.center, style: DFTextStyles.caption.copyWith(fontSize: 11)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _activeTabIndex = 0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DFColors.surface,
                  foregroundColor: DFColors.primaryStitch,
                  side: const BorderSide(color: DFColors.primaryStitch),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('View Overview'),
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final user = ref.watch(userProfileProvider).value;
                  if (user?.role == UserRole.manager || user?.role == UserRole.admin) {
                    return SizedBox(
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
                          elevation: 4,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
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
                  child: const Icon(Icons.check_circle_outline,
                      size: 32, color: DFColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text('No Deviations Detected',
                    style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                    'Project is currently running within expected material and budget benchmarks.',
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
              const SizedBox(height: 4),
              Text(
                  'I have analyzed your logs and estimates. How can I help you?',
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
}
