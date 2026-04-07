import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  int _activeTabIndex = 0;

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DFColors.primaryStitch),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(color: DFColors.primaryContainerStitch, shape: BoxShape.circle),
              clipBehavior: Clip.hardEdge,
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Project Details', style: DFTextStyles.screenTitle.copyWith(fontSize: 18, color: DFColors.textPrimary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: DFColors.primaryStitch),
            onPressed: () => context.push('/projects/${widget.projectId}/pdf-preview'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: DFColors.primaryStitch),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: projectAsync.when(
        data: (project) {
          if (project == null) return const Center(child: Text('PROJECT NOT FOUND'));

          return Column(
            children: [
              // Tab Bar
              Container(
                color: Colors.white.withValues(alpha: 0.95),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                      _buildProjectHeader(project, deviationAsync.asData?.value),
                      Padding(
                        padding: const EdgeInsets.all(24.0).copyWith(bottom: 150),
                        child: _activeTabIndex == 0 ? _buildOverviewTab(project, estimateAsync.asData?.value) :
                               _activeTabIndex == 1 ? _buildEstimatesTab() :
                               _activeTabIndex == 2 ? _buildDeviationsTab(deviationAsync.asData?.value) :
                               _buildAiChatTab(project),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
        error: (e, _) => Center(child: Text('ERR: $e', style: DFTextStyles.caption.copyWith(color: DFColors.critical))),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => context.push('/projects/${widget.projectId}/log-entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DFColors.primaryStitch,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 8,
                  shadowColor: DFColors.primaryStitch.withValues(alpha: 0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_task_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Log Entry', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              onPressed: () => context.push('/projects/${widget.projectId}/ai-chat'),
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

  Widget _buildProjectHeader(ProjectModel project, Map<String, dynamic>? latestDev) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');
    final dateFormat = DateFormat('MMM yyyy');
    
    // Calculate progress based on time
    final totalDays = project.expectedEndDate.difference(project.startDate).inDays;
    final elapsedDays = DateTime.now().difference(project.startDate).inDays;
    final timeProgress = (elapsedDays / totalDays).clamp(0.0, 1.0);
    
    // Mock utilization based on time + small jitter
    final utilization = (timeProgress * 0.95 + 0.05).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x0A191C1E), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(4)),
                          child: Text(project.status.name.toUpperCase(), style: DFTextStyles.labelSm.copyWith(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(project.location, style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(project.name, style: DFTextStyles.screenTitle.copyWith(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.2)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: DFColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${dateFormat.format(project.startDate)} – ${dateFormat.format(project.expectedEndDate)}', style: DFTextStyles.body.copyWith(fontSize: 12, color: DFColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TOTAL BUDGET', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryContainerStitch, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(currencyFormat.format(project.plannedBudget), style: DFTextStyles.screenTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w900, color: DFColors.primaryStitch)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spend Progress', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.textSecondary, fontSize: 11)),
              Text('${(utilization * 100).toInt()}% Utilized', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity, height: 12,
            decoration: BoxDecoration(color: DFColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft, widthFactor: utilization,
              child: Container(decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [DFColors.primaryStitch, DFColors.primaryContainerStitch]),
                borderRadius: BorderRadius.circular(6)
              )),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isActive ? DFColors.primaryStitch : Colors.transparent, width: 2)),
        ),
        child: Text(title, style: DFTextStyles.body.copyWith(
          color: isActive ? DFColors.primaryStitch : DFColors.textSecondary,
          fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
        )),
      ),
    );
  }

  Widget _buildOverviewTab(ProjectModel project, EstimateModel? latestEstimate) {
    final totalDays = project.expectedEndDate.difference(project.startDate).inDays;
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
        if (key.toLowerCase().contains('cement')) matValues['cement'] = val['quantity'].toString();
        if (key.toLowerCase().contains('brick')) matValues['bricks'] = val['quantity'].toString();
        if (key.toLowerCase().contains('steel')) matValues['steel'] = val['quantity'].toString();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Project Timeline'),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2))),
          child: Column(
            children: [
              Container(
                width: double.infinity, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: DFColors.outlineVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft, widthFactor: timeProgress,
                      child: Container(decoration: BoxDecoration(color: DFColors.primaryStitch, borderRadius: BorderRadius.circular(2))),
                    ),
                    Positioned(top: -6, left: 0, child: _buildTimelineDot(active: true)),
                    Positioned(top: -6, left: (MediaQuery.of(context).size.width - 96) * timeProgress, child: _buildTimelineDot(active: true, hasRing: true)),
                    Positioned(top: -6, right: 0, child: _buildTimelineDot(active: false)),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateFormat.format(project.startDate), style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  Text('TODAY', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  Text(dateFormat.format(project.expectedEndDate), style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        _buildSectionTitle('Material Estimations'),
        Row(
          children: [
            Expanded(child: _buildMaterialEstimationCard('Total Cement', matValues['cement'], 'Bags', Icons.trending_up, 'Stable', const Color(0xFF16A34A), const Color(0xFFDCFCE7))),
            const SizedBox(width: 12),
            Expanded(child: _buildMaterialEstimationCard('Total Bricks', matValues['bricks'], 'Nos', Icons.horizontal_rule, 'Normal', const Color(0xFF2563EB), const Color(0xFFDBEAFE))),
          ],
        ),
        const SizedBox(height: 12),
        _buildMaterialEstimationCard('Total Steel', matValues['steel'], 'Kg', Icons.warning_rounded, 'Price High', const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
        
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('On-Site Team'),
            Consumer(
              builder: (context, ref, _) {
                final userRole = ref.watch(userProfileProvider).value?.role;
                final isManager = userRole == UserRole.manager || userRole == UserRole.admin;
                return TextButton.icon(
                  onPressed: () => context.push('/projects/${widget.projectId}/team'),
                  icon: Icon(isManager ? Icons.group_add_rounded : Icons.groups_rounded, size: 16),
                  label: Text(
                    isManager ? 'MANAGE TEAM' : 'VIEW TEAM', 
                    style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.5,
          ),
          itemCount: project.teamMembers.length > 4 ? 4 : project.teamMembers.length,
          itemBuilder: (context, index) {
            final uid = project.teamMembers[index];
            return Consumer(
              builder: (context, ref, _) {
                final userAsync = ref.watch(userByIdProvider(uid));
                
                return userAsync.when(
                  data: (user) {
                    if (user == null) {
                      return _buildTeamMember('Unknown Staff', 'Engineer', isOthers: false);
                    }
                    return _buildTeamMember(
                      user.name, 
                      user.designation ?? (user.role == UserRole.manager ? 'Project Manager' : 'Site Engineer'), 
                      isOthers: false
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, __) => _buildTeamMember('Error Loading', 'Identity Error', isOthers: false),
                );
              },
            );
          },
        ),
        
        const SizedBox(height: 32),
        _buildSectionTitle('Manpower & Attendance'),
        Row(
          children: [
            Expanded(
              child: DFCard(
                onTap: () => context.push('/projects/${widget.projectId}/workforce'),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.analytics_outlined, color: DFColors.primaryStitch, size: 24),
                    const SizedBox(height: 16),
                    Text('WORKFORCE OVERVIEW', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('View trade-wise stats and daily headcounts.', style: DFTextStyles.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Consumer(
              builder: (context, ref, _) {
                final userRole = ref.watch(userProfileProvider).value?.role;
                if (userRole == UserRole.engineer || userRole == UserRole.manager || userRole == UserRole.admin) {
                  return Expanded(
                    child: DFCard(
                      onTap: () => context.push('/projects/${widget.projectId}/attendance'),
                      padding: const EdgeInsets.all(20),
                      color: DFColors.primaryStitch.withValues(alpha: 0.05),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.how_to_reg_rounded, color: DFColors.primaryStitch, size: 24),
                          const SizedBox(height: 16),
                          Text('MARK ATTENDANCE', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Log daily presence for your site team.', style: DFTextStyles.caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        
        const SizedBox(height: 32),
        _buildSectionTitle('Financial Documents'),
        Consumer(
          builder: (context, ref, _) {
            final userRole = ref.watch(userProfileProvider).value?.role;
            final isAuthorized = userRole == UserRole.engineer || userRole == UserRole.manager || userRole == UserRole.admin;
            
            return Row(
              children: [
                Expanded(
                  child: DFCard(
                    onTap: isAuthorized 
                      ? () => context.push('/projects/\${widget.projectId}/bills/upload')
                      : null,
                    padding: const EdgeInsets.all(20),
                    color: isAuthorized ? DFColors.primaryStitch.withValues(alpha: 0.05) : Colors.grey[100],
                    child: Opacity(
                      opacity: isAuthorized ? 1.0 : 0.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.receipt_long_outlined, color: DFColors.primaryStitch, size: 24),
                          const SizedBox(height: 16),
                          Text('UPLOAD VENDOR BILL', style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Archive digital copies of site invoices.', style: DFTextStyles.caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Spacer(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimelineDot({required bool active, bool hasRing = false}) {
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: active ? DFColors.primaryStitch : DFColors.outlineVariant,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: hasRing ? [BoxShadow(color: DFColors.primaryStitch.withValues(alpha: 0.2), spreadRadius: 4)] : null,
      ),
    );
  }

  Widget _buildMaterialEstimationCard(String title, String value, String unit, IconData icon, String statusLabel, Color statusColor, Color statusBg) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: DFTextStyles.screenTitle.copyWith(fontSize: 22, height: 1.0)),
              const SizedBox(width: 4),
              Text(unit, style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(statusLabel, style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamMember(String name, String role, {required bool isOthers}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1))),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: isOthers ? DFColors.primaryContainerStitch :Colors.grey[300], borderRadius: BorderRadius.circular(8)),
            child: isOthers 
              ? const Center(child: Text('+5', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))
              : const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: DFTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text(role, style: DFTextStyles.caption.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
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

  Widget _buildDeviationsTab(Map<String, dynamic>? devData) {
    if (devData == null || devData['overallSeverity'] == 'normal') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Deviations'),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(color: DFColors.surfaceContainerLow.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1))),
            child: Column(
              children: [
                Container(
                  width: 64, height: 64, decoration: const BoxDecoration(color: DFColors.surfaceContainerHighest, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline, size: 32, color: DFColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text('No Deviations Detected', style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
                const SizedBox(height: 4),
                Text('Project is currently running within expected material and budget benchmarks.', 
                  textAlign: TextAlign.center, style: DFTextStyles.body.copyWith(fontSize: 14, color: DFColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }

    final severity = devData['overallSeverity'] as String;
    final prob = (devData['mlOverrunProbability'] as num? ?? 0.0) * 100;
    final reason = devData['reason'] ?? 'Unusual resource consumption patterns detected.';
    final insight = devData['aiInsight'] ?? 'Monitor site logs for the next 48 hours.';

    Color color = severity == 'critical' ? const Color(0xFFB10010) : const Color(0xFFFEA619);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Active Deviation'),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(severity == 'critical' ? Icons.error_rounded : Icons.warning_rounded, color: color),
                  const SizedBox(width: 12),
                  Text(severity.toUpperCase(), style: DFTextStyles.screenTitle.copyWith(fontSize: 18, color: color)),
                ],
              ),
              const SizedBox(height: 16),
              Text(reason, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(insight, style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Overrun Risk', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
                  Text('${prob.toInt()}%', style: DFTextStyles.screenTitle.copyWith(fontSize: 24, color: color)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: prob / 100,
                  backgroundColor: DFColors.surfaceContainerHighest,
                  color: color,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      ],
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
                width: 56, height: 56, decoration: BoxDecoration(color: DFColors.primaryStitch, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x4D003E7E), blurRadius: 16, offset: Offset(0, 8))]),
                child: const Icon(Icons.smart_toy_outlined, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text('Context: ${project.name}', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('I have analyzed your logs and estimates. How can I help you?', textAlign: TextAlign.center, style: DFTextStyles.body.copyWith(fontSize: 14, color: DFColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildChatPrompt('Explain recent cement spikes?', Icons.query_stats),
        const SizedBox(height: 12),
        _buildChatPrompt("Compare logs with CAD estimates", Icons.inventory_2_outlined),
      ],
    );
  }

  Widget _buildChatPrompt(String text, IconData icon) {
    return InkWell(
      onTap: () => context.push('/projects/${widget.projectId}/ai-chat'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: DFColors.primaryStitch),
            const SizedBox(width: 12),
            Text(text, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 16, color: DFColors.primaryContainerStitch)),
    );
  }

}
