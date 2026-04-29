import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../models/project_model.dart';
import '../../models/resource_log_model.dart';
import '../../utils/design_tokens.dart';
import '../../providers/weather_provider.dart';
import '../../models/weather_model.dart';
import '../../providers/delay_notice_provider.dart';
import '../../models/delay_notice_model.dart';
import '../delays/create_delay_notice_screen.dart';
import '../delays/delay_notice_detail_screen.dart';
import '../delays/delay_notices_list_screen.dart';
import '../../widgets/df_button.dart';

class EngineerHome extends ConsumerWidget {
  const EngineerHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    return Scaffold(
      backgroundColor: DFColors.background,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0), // Above nav bar
        child: FloatingActionButton.extended(
          onPressed: () {
            final projects = projectsAsync.value ?? [];
            final selectedId = ref.read(selectedProjectIdProvider);
            final project = projects.firstWhere((p) => p.projectId == selectedId, orElse: () => projects.first);
            
            context.push('/projects/${project.projectId}/log-entry');
          },
          backgroundColor: const Color(0xFF1A56A0),
          foregroundColor: Colors.white,
          elevation: 8,
          icon: const Icon(Icons.add_rounded, size: 28),
          label: Text("Log Today's Resources", style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.2)),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          _buildTopAppBar(context),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreetingSection(userProfile?.name ?? 'Engineer'),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // 🌤️ Weather Banner
          SliverToBoxAdapter(
            child: _buildWeatherBanner(ref, projectsAsync.value ?? []),
          ),

          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) {
                return const SliverToBoxAdapter(
                  child: const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No active assignments.'),
                  )),
                );
              }

              // Determine selected project
              final selectedId = ref.watch(selectedProjectIdProvider);
              final primaryProject = projects.firstWhere(
                (p) => p.projectId == selectedId, 
                orElse: () => projects.first
              );

              // Fetch live stats and logs for the selected project
              final logsAsync = ref.watch(projectLogsProvider(primaryProject.projectId));
              final deviationsAsync = ref.watch(projectDeviationsStreamProvider(primaryProject.projectId));

              final logs = logsAsync.value ?? [];
              final deviations = deviationsAsync.value ?? [];

              // Calculate "Logs This Week"
              final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
              final weeklyLogsCount = logs.where((l) => l.logDate.isAfter(sevenDaysAgo)).length;

              // Calculate "Today's Status"
              final now = DateTime.now();
              final hasLogToday = logs.any((l) => 
                l.logDate.year == now.year && 
                l.logDate.month == now.month && 
                l.logDate.day == now.day
              );

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0).copyWith(bottom: 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildAssignedProjectCard(context, primaryProject),
                    const SizedBox(height: 24),
                    _buildQuickStatsRow(
                      weeklyLogsCount: weeklyLogsCount,
                      hasLogToday: hasLogToday,
                      deviationsCount: deviations.length,
                    ),
                    const SizedBox(height: 24),
                    _buildActionButtons(context, primaryProject.projectId),
                    const SizedBox(height: 32),
                    
                    _buildPendingVotesSection(context, ref, primaryProject.projectId, userProfile?.uid ?? ''),
                    
                    // Below stats, we have Recent Entries and AI Assistant Side-by-Side (or stacked on mobile)
                    _buildRecentEntriesHeader(context, primaryProject.projectId),
                    const SizedBox(height: 16),
                    _buildRecentEntriesList(context, primaryProject, logs),
                    const SizedBox(height: 24),
                    _buildAiAssistantShortcut(context, primaryProject),
                    const SizedBox(height: 16),
                    _buildGuidanceTip(),
                  ]),
                ),
              );
            },
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: DFColors.primaryStitch))),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      'STATION ERROR: $e', 
                      textAlign: TextAlign.center,
                      style: DFTextStyles.caption.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: DFColors.surface.withValues(alpha: 0.9),
      elevation: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: DFColors.primaryContainerStitch,
            ),
            clipBehavior: Clip.hardEdge,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ConstructIQ', 
                style: DFTextStyles.screenTitle.copyWith(
                  color: DFColors.textPrimary, 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                )
              ),
              Text('Site Engineer Portal', 
                style: DFTextStyles.labelSm.copyWith(
                  color: DFColors.textSecondary, 
                  fontSize: 11, 
                  fontWeight: FontWeight.w500,
                )
              ),
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined, color: DFColors.textSecondary),
            onPressed: () => context.go('/notifications'),
            hoverColor: DFColors.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  Widget _buildGreetingSection(String name) {
    String formattedDate = DateFormat('MMM d, yyyy').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Greetings ${name.split(' ').first}', 
                style: DFTextStyles.screenTitle.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: DFColors.textPrimary,
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 4)),
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Transform.translate(
                  offset: const Offset(0, -10),
                  child: Text(formattedDate, 
                    style: DFTextStyles.body.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: DFColors.textSecondary.withValues(alpha: 0.8),
                      letterSpacing: 0.5,
                    )
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text("Site Overview", 
                style: DFTextStyles.screenTitle.copyWith(
                  fontSize: 20, 
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: DFColors.textSecondary.withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Consumer(
              builder: (context, ref, _) {
                final projects = ref.watch(projectListProvider).value ?? [];
                if (projects.length <= 1) return const SizedBox.shrink();
                
                return TextButton.icon(
                  onPressed: () => _showProjectPicker(context, ref, projects),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: Text('SWITCH SITE', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
                  style: TextButton.styleFrom(
                    backgroundColor: DFColors.primaryStitch.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                );
              },
            ),
          ],
        ),
        Text("Engineer: $name", 
          style: DFTextStyles.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: DFColors.textSecondary,
          )
        ),
      ],
    );
  }

  void _showProjectPicker(BuildContext context, WidgetRef ref, List<ProjectModel> projects) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DFColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switch Active Site', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: projects.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final isSelected = ref.read(selectedProjectIdProvider) == project.projectId;
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(project.name, style: DFTextStyles.body.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(project.location, style: DFTextStyles.caption),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: DFColors.primaryStitch) : null,
                    onTap: () {
                      ref.read(selectedProjectIdProvider.notifier).state = project.projectId;
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedProjectCard(BuildContext context, ProjectModel project) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D3470), // Deep Industrial Blue
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x330D3470), blurRadius: 20, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -20, top: -20,
            child: Icon(Icons.engineering_rounded, size: 140, color: Colors.white.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFFEA619), borderRadius: BorderRadius.circular(4)),
                      child: Text('LIVE ASSIGNMENT', style: DFTextStyles.labelSm.copyWith(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
                    ),
                    const Spacer(),
                    const Icon(Icons.sensors_rounded, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('ON-SITE', style: DFTextStyles.labelSm.copyWith(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(project.name, style: DFTextStyles.screenTitle.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(project.location, style: DFTextStyles.body.copyWith(color: Colors.white70, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final managerAsync = ref.watch(userNameProvider(project.createdBy));
                          return _buildProjectMetric(
                            'MANAGER', 
                            managerAsync.when(
                              data: (name) => name,
                              loading: () => 'Loading...',
                              error: (_, __) => 'Site Manager',
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _buildProjectMetric('DEADLINE', 'JUN 2026')),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => context.push('/projects/${project.projectId}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0D3470),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('SITE LOGS & BLUEPRINTS', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.0, color: const Color(0xFF0D3470))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DFTextStyles.labelSm.copyWith(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Text(value, style: DFTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildQuickStatsRow({
    required int weeklyLogsCount,
    required bool hasLogToday,
    required int deviationsCount,
  }) {
    return Column(
      children: [
        _buildStatCard(
          title: 'Logs This Week', 
          value: weeklyLogsCount.toString(), 
          icon: Icons.history, 
          iconBgColor: DFColors.surfaceContainerHighest, 
          iconColor: DFColors.primaryStitch
        ),
        const SizedBox(height: 24),
        _buildStatCard(
          title: "Today's Status", 
          value: hasLogToday ? 'Submitted' : 'Pending', 
          icon: hasLogToday ? Icons.check_circle_outline : Icons.pending_actions_rounded, 
          iconBgColor: hasLogToday 
              ? const Color(0xFF16A34A).withValues(alpha: 0.1) 
              : const Color(0xFFFEA619).withValues(alpha: 0.2), 
          iconColor: hasLogToday ? const Color(0xFF166534) : const Color(0xFF855300),
          valueIcon: hasLogToday ? Icons.verified : Icons.schedule, 
          valueIconColor: hasLogToday ? const Color(0xFF166534) : const Color(0xFF855300)
        ),
        const SizedBox(height: 24),
        _buildStatCard(
          title: 'Deviations', 
          value: deviationsCount.toString(), 
          suffix: deviationsCount == 1 ? 'flagged' : 'total', 
          icon: Icons.warning_amber_rounded, 
          iconBgColor: deviationsCount > 0 
              ? const Color(0xFFB10010).withValues(alpha: 0.1) 
              : DFColors.surfaceContainerHighest, 
          iconColor: deviationsCount > 0 ? const Color(0xFF850009) : DFColors.textSecondary,
          valueColor: deviationsCount > 0 ? const Color(0xFF850009) : DFColors.textPrimary, 
          borderLeftColor: deviationsCount > 0 ? const Color(0xFFB10010) : null
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title, required String value, String? suffix, required IconData icon, 
    required Color iconBgColor, required Color iconColor, Color? valueColor, 
    IconData? valueIcon, Color? valueIconColor, Color? borderLeftColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: borderLeftColor != null ? Border(left: BorderSide(color: borderLeftColor, width: 4)) : null,
        boxShadow: const [BoxShadow(color: Color(0x0A191C1E), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: DFTextStyles.labelSm.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: DFColors.textSecondary, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value, style: DFTextStyles.screenTitle.copyWith(fontSize: 28, height: 1.0, color: valueColor ?? DFColors.textPrimary)),
                    if (suffix != null) ...[
                      const SizedBox(width: 4),
                      Text(suffix, style: DFTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
                    ],
                    if (valueIcon != null) ...[
                      const SizedBox(width: 6),
                      Icon(valueIcon, size: 20, color: valueIconColor),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEntriesHeader(BuildContext context, String projectId) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Recent Entries', style: DFTextStyles.screenTitle.copyWith(fontSize: 16, color: DFColors.primaryContainerStitch)),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DelayNoticesListScreen(projectId: projectId))),
              child: Text('NOTICES', style: DFTextStyles.labelSm.copyWith(color: DFColors.warning, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text('See All', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, String projectId) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.warning_amber_outlined, size: 18),
            label: const Text('File Delay Notice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DFColors.warning,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => CreateDelayNoticeScreen(projectId: projectId))),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingVotesSection(BuildContext context, WidgetRef ref, String projectId, String currentUid) {
    final pendingVotes = ref.watch(pendingVotesProvider((
      projectId: projectId, uid: currentUid)));

    return pendingVotes.when(
      data: (notices) {
        if (notices.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote_rounded, color: DFColors.warning, size: 16),
                const SizedBox(width: 8),
                Text('VOTE REQUIRED', style: DFTextStyles.labelSm.copyWith(
                  color: DFColors.warning, fontWeight: FontWeight.bold, letterSpacing: 1.1,
                )),
              ],
            ),
            const SizedBox(height: 12),
            ...notices.map((notice) => _PendingVoteCard(
              notice: notice,
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DelayNoticeDetailScreen(notice: notice, projectId: projectId))),
            )),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentEntriesList(BuildContext context, ProjectModel project, List<ResourceLogModel> logs) {
    if (logs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: DFColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(Icons.assignment_late_outlined, color: DFColors.textSecondary.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            Text('No log entries yet.', style: DFTextStyles.body.copyWith(color: DFColors.textSecondary)),
          ],
        ),
      );
    }

    final recentLogs = logs.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.hardEdge,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recentLogs.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: DFColors.surfaceContainerLow),
        itemBuilder: (context, index) {
          final log = recentLogs[index];
          final month = DateFormat('MMM').format(log.logDate);
          final day = DateFormat('dd').format(log.logDate);
          
          // Simple summary from materials
          String summary = "";
          if (log.materials.isNotEmpty) {
            final first = log.materials.entries.first;
            summary = "${first.value.toStringAsFixed(0)} ${first.key}";
            if (log.materials.length > 1) summary += ", +${log.materials.length - 1} more";
          } else {
            summary = "Resource log submitted";
          }

          return _buildLogEntryRow(
            month, 
            day, 
            log.notes.isNotEmpty ? log.notes : "Daily Progress Log", 
            summary, 
            'VERIFIED', 
            false
          );
        },
      ),
    );
  }

  Widget _buildLogEntryRow(String month, String day, String title, String desc, String badgeText, bool isCritical) {
    Color bgFill = isCritical ? const Color(0xFFB10010).withValues(alpha: 0.05) : DFColors.surface;
    Color dateHeaderColor = isCritical ? const Color(0xFFB10010) : DFColors.textSecondary;
    Color dateNumColor = isCritical ? const Color(0xFF850009) : DFColors.textPrimary;
    Color titleColor = isCritical ? const Color(0xFF850009) : DFColors.textPrimary;
    Color badgeColor = isCritical ? const Color(0xFFB10010) : DFColors.surfaceContainerHighest;
    Color badgeTextColor = isCritical ? Colors.white : DFColors.textPrimary;

    return Container(
      color: bgFill,
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Column(
              children: [
                Text(month.toUpperCase(), style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: dateHeaderColor)),
                Text(day, style: DFTextStyles.screenTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w900, color: dateNumColor)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: titleColor)),
                const SizedBox(height: 2),
                Text(desc, style: DFTextStyles.body.copyWith(fontSize: 14, color: DFColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(16)),
            child: Text(badgeText, style: DFTextStyles.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: badgeTextColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssistantShortcut(BuildContext context, ProjectModel project) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DFColors.primaryStitch,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x33003E7E), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text('Ask the AI Assistant', style: DFTextStyles.screenTitle.copyWith(fontSize: 18, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Get insights about your project specs or safety guidelines instantly.', style: DFTextStyles.body.copyWith(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: () => context.push('/projects/${project.projectId}/ai-chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: DFColors.primaryStitch,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Start Chat', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceTip() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded, size: 36, color: DFColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('Quick Tip', style: DFTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
          const SizedBox(height: 4),
          Text("Don't forget to upload today's site photos with your resource log for automated visual verification.", 
            textAlign: TextAlign.center,
            style: DFTextStyles.caption.copyWith(fontSize: 12, height: 1.5, color: DFColors.textSecondary)
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🌤️ WEATHER BANNER
  // ═══════════════════════════════════════════════════════════════
  static Widget _buildWeatherBanner(WidgetRef ref, List<ProjectModel> projects) {
    if (projects.isEmpty) return const SizedBox.shrink();

    final weatherAsync = ref.watch(projectWeatherProvider(projects.first.projectId));

    return weatherAsync.when(
      data: (weather) {
        if (weather == null) return const SizedBox.shrink();

        final isAdverse = weather.isAdverse;
        final bgColor = isAdverse ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9);
        final iconColor = isAdverse ? const Color(0xFFE65100) : const Color(0xFF2E7D32);
        final advisory = isAdverse
            ? 'Adverse weather — Work may be limited today'
            : 'Weather is clear for site operations';

        IconData icon;
        switch (weather.condition.toLowerCase()) {
          case 'clear':
            icon = Icons.wb_sunny_rounded;
            break;
          case 'clouds':
            icon = Icons.cloud_rounded;
            break;
          case 'rain':
          case 'drizzle':
            icon = Icons.water_drop_rounded;
            break;
          case 'thunderstorm':
            icon = Icons.thunderstorm_rounded;
            break;
          default:
            icon = Icons.cloud_rounded;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${weather.temperature.round()}°C · ${weather.description}',
                        style: DFTextStyles.body.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 13, color: iconColor)),
                      Text(advisory,
                        style: DFTextStyles.caption.copyWith(
                          fontSize: 10, color: iconColor.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Text(weather.cityName,
                  style: DFTextStyles.caption.copyWith(fontSize: 9, color: iconColor.withValues(alpha: 0.5))),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _PendingVoteCard extends StatelessWidget {
  final DelayNotice notice;
  final VoidCallback onTap;

  const _PendingVoteCard({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DFColors.warning, width: 1),
      ),
      color: DFColors.warningBg.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notice.title, style: DFTextStyles.cardTitle.copyWith(fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'Filed by ${notice.createdByName} on ${DateFormat('MMM dd').format(notice.reportedDate)}',
                      style: DFTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: DFColors.warning),
                  const SizedBox(height: 4),
                  Text('TAP TO VOTE', style: DFTextStyles.labelSm.copyWith(
                    color: DFColors.warning, fontWeight: FontWeight.bold, fontSize: 9,
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
