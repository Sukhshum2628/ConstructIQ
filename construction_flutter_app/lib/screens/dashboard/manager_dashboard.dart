import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../models/project_model.dart';
import '../../utils/design_tokens.dart';
import '../../utils/firestore_seeder.dart';

class ManagerDashboard extends ConsumerStatefulWidget {
  const ManagerDashboard({super.key});

  @override
  ConsumerState<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends ConsumerState<ManagerDashboard> {
  String? _selectedChartProjectId;

  Future<void> _reSeedDatabase() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seeding database...'), duration: Duration(seconds: 1)),
    );
    try {
      await FirestoreSeeder.seedAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Seeding complete! Refreshing data...')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Seeding failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);
    final summaryAsync = ref.watch(deviationSummaryProvider);
    final allDeviationsAsync = ref.watch(allDeviationsProvider);
    final userProfile = ref.watch(userProfileProvider).value;

    // Calculate Avg Overrun Risk from all projects
    double avgRisk = 0.0;
    if (allDeviationsAsync.hasValue && allDeviationsAsync.value!.isNotEmpty) {
      final risks = allDeviationsAsync.value!
          .map((d) => (d['mlOverrunProbability'] as num? ?? 0.0).toDouble())
          .toList();
      avgRisk = risks.reduce((a, b) => a + b) / risks.length * 100;
    } else {
      avgRisk = 12.5; // Fallback to mockup value if no data
    }

    return Scaffold(
      backgroundColor: DFColors.background,
      body: CustomScrollView(
        slivers: [
          _buildTopAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreetingSection(userProfile?.name ?? 'Manager'),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          
          // Horizontal Summary Cards
          SliverToBoxAdapter(
            child: _buildSummaryCards(projectsAsync.value ?? [], summaryAsync.value ?? {}, avgRisk),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTrendSection(projectsAsync.value ?? []),
                  const SizedBox(height: 32),
                  _buildProjectStatusHeader(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Project List
          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('No active projects')),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0).copyWith(bottom: 96),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ProjectRiskCard(project: projects[index]),
                    childCount: projects.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: DFColors.primaryStitch))),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('Error: $e', style: DFTextStyles.body.copyWith(color: DFColors.critical)))),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: DFColors.surface.withValues(alpha: 0.9),
      elevation: 0,
      titleSpacing: 24,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DFColors.primaryContainerStitch,
              border: Border.all(color: Colors.white, width: 2),
            ),
            clipBehavior: Clip.hardEdge,
            child: const Icon(Icons.person, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Text('ConstructIQ', 
            style: DFTextStyles.screenTitle.copyWith(
              color: DFColors.primaryStitch, 
              fontSize: 20, 
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            )
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.sync_rounded, color: DFColors.primaryStitch),
          onPressed: _reSeedDatabase,
          tooltip: 'Re-sync Data',
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: DFColors.primaryStitch),
                onPressed: () => context.push('/notifications'),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBA1A1A),
                    shape: BoxShape.circle,
                    border: Border.all(color: DFColors.background, width: 2),
                  ),
                ),
              ),
            ],
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
        Text('Good morning, ${name.split(' ').first}', 
          style: DFTextStyles.screenTitle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: DFColors.textPrimary,
          )
        ),
        const SizedBox(height: 4),
        Text(formattedDate, 
          style: DFTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: DFColors.textSecondary,
          )
        ),
      ],
    );
  }

  Widget _buildSummaryCards(List<ProjectModel> projects, Map<String, int> summary, double avgRisk) {
    int activeCount = projects.where((p) => p.status == ProjectStatus.active).length;
    int warningCount = summary['warnings'] ?? 0;
    int criticalCount = summary['criticals'] ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        children: [
          _buildHorizontalCard(
            title: 'Active Projects',
            value: activeCount.toString(),
            bgColor: DFColors.primaryContainerStitch,
            textColor: Colors.white,
            shadowColor: const Color(0x261A56A0),
          ),
          const SizedBox(width: 16),
          _buildHorizontalCard(
            title: 'Warning',
            value: warningCount.toString(),
            bgColor: const Color(0xFFFEA619),
            textColor: const Color(0xFF2A1700),
            shadowColor: const Color(0x26FEA619),
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 16),
          _buildHorizontalCard(
            title: 'Critical',
            value: criticalCount.toString(),
            bgColor: const Color(0xFFB10010),
            textColor: Colors.white,
            shadowColor: const Color(0x26B10010),
            icon: Icons.error_rounded,
          ),
          const SizedBox(width: 16),
          Container(
            width: 160,
            height: 128,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DFColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
              boxShadow: const [
                BoxShadow(color: Color(0x0A191C1E), blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Avg Overrun Risk', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${avgRisk.toStringAsFixed(1)}%', style: DFTextStyles.screenTitle.copyWith(fontSize: 28, color: const Color(0xFF855300), height: 1.0)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 4,
                      decoration: BoxDecoration(color: DFColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (avgRisk / 100.0).clamp(0.0, 1.0),
                        child: Container(decoration: BoxDecoration(color: const Color(0xFF855300), borderRadius: BorderRadius.circular(4))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard({
    required String title,
    required String value,
    required Color bgColor,
    required Color textColor,
    required Color shadowColor,
    IconData? icon,
  }) {
    return Container(
      width: 160,
      height: 128,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: shadowColor, blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: textColor),
                const SizedBox(width: 4),
              ],
              Text(title.toUpperCase(), style: DFTextStyles.labelSm.copyWith(color: textColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 11)),
            ],
          ),
          Text(value, style: DFTextStyles.screenTitle.copyWith(fontSize: 36, color: textColor, height: 1.0)),
        ],
      ),
    );
  }

  Widget _buildTrendSection(List<ProjectModel> projects) {
    if (projects.isEmpty) return const SizedBox();
    
    _selectedChartProjectId ??= projects.first.projectId;
    
    final logsAsync = ref.watch(resourceLogsProvider(_selectedChartProjectId!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Usage Trend', 
                    style: DFTextStyles.screenTitle.copyWith(fontSize: 18, color: DFColors.textPrimary, fontWeight: FontWeight.bold)
                  ),
                  Text('7-day cumulative consumption', 
                    style: DFTextStyles.body.copyWith(fontSize: 12, color: DFColors.textSecondary)
                  ),
                ],
              ),
            ),
            _buildLegendItem(label: 'Cement', color: const Color(0xFFFEA619)),
            const SizedBox(width: 12),
            _buildLegendItem(label: 'Bricks', color: const Color(0xFF5C6BC0)),
            const SizedBox(width: 12),
            _buildLegendItem(label: 'Steel', color: const Color(0xFF26A69A)),
          ],
        ),
        const SizedBox(height: 12),
        // Project Selector Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: projects.map((p) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(p.name, style: TextStyle(
                  color: _selectedChartProjectId == p.projectId ? Colors.white : DFColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
                selected: _selectedChartProjectId == p.projectId,
                selectedColor: DFColors.primaryStitch,
                backgroundColor: DFColors.surfaceContainerLow,
                elevation: 0,
                pressElevation: 0,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedChartProjectId = p.projectId;
                    });
                  }
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 280,
          padding: const EdgeInsets.fromLTRB(12, 24, 24, 16),
          decoration: BoxDecoration(
            color: DFColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
            boxShadow: const [
              BoxShadow(color: Color(0x0F191C1E), blurRadius: 40, offset: Offset(0, 12)),
            ],
          ),
          child: logsAsync.when(
            data: (logs) {
              if (logs.isEmpty) {
                return const Center(child: Text('No data for last 7 days'));
              }

              // Sort logs by date ascending (oldest first)
              final sortedLogs = List<Map<String, dynamic>>.from(logs);
              sortedLogs.sort((a, b) => (a['logDate'] as Timestamp).compareTo(b['logDate'] as Timestamp));

              // Map to chart spots using index 0..6 for strictly increasing X
              final cementSpots = <FlSpot>[];
              final brickSpots = <FlSpot>[];
              final steelSpots = <FlSpot>[];

              for (int i = 0; i < sortedLogs.length; i++) {
                final mats = sortedLogs[i]['materials'] as Map<String, dynamic>;
                cementSpots.add(FlSpot(i.toDouble(), (mats['cement'] as num? ?? 0).toDouble()));
                brickSpots.add(FlSpot(i.toDouble(), (mats['bricks'] as num? ?? 0).toDouble()));
                steelSpots.add(FlSpot(i.toDouble(), (mats['steel'] as num? ?? 0).toDouble()));
              }

              return Column(
                children: [
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 50,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: DFColors.outlineVariant.withValues(alpha: 0.3), 
                            strokeWidth: 1,
                            dashArray: [5, 5],
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                if (value == meta.max || value == meta.min) return const SizedBox();
                                return Text(value.toInt().toString(), 
                                  style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontSize: 10)
                                );
                              },
                            )
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= sortedLogs.length) return const SizedBox();
                                
                                final date = (sortedLogs[index]['logDate'] as Timestamp).toDate();
                                final label = DateFormat('E').format(date).toUpperCase(); // e.g. "MON", "TUE"

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(label, 
                                    style: DFTextStyles.labelSm.copyWith(
                                      color: DFColors.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    )
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipBgColor: DFColors.primaryStitch,
                            getTooltipItems: (items) => items.map((item) {
                              String label = '';
                              String unit = '';
                              if (item.barIndex == 0) { label = 'Cement'; unit = 'Bags'; }
                              else if (item.barIndex == 1) { label = 'Bricks'; unit = 'Nos'; }
                              else if (item.barIndex == 2) { label = 'Steel'; unit = 'Kg'; }
                              
                              return LineTooltipItem(
                                '$label: ${item.y.toInt()} $unit',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              );
                            }).toList(),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          _buildLineBarData(spots: cementSpots, color: const Color(0xFFFEA619)),
                          _buildLineBarData(spots: brickSpots, color: const Color(0xFF5C6BC0)),
                          _buildLineBarData(spots: steelSpots, color: const Color(0xFF26A69A)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
            error: (e, _) => Center(child: Text('Err loading logs: $e')),
          ),
        ),
      ],
    );
  }

  LineChartBarData _buildLineBarData({required List<FlSpot> spots, required Color color}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 3,
          color: Colors.white,
          strokeWidth: 1.5,
          strokeColor: color,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _buildLegendItem({required String label, required Color color, bool isDashed = false}) {
    return Row(
      children: [
        if (isDashed)
          Container(
            width: 12, height: 2,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color, width: 2, style: BorderStyle.none))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(width: 4, height: 2, color: color),
                const SizedBox(width: 4),
                Container(width: 4, height: 2, color: color),
              ],
            ),
          )
        else
          Container(width: 12, height: 2, color: color),
        const SizedBox(width: 8),
        Text(label, style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 11)),
      ],
    );
  }

  Widget _buildProjectStatusHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text('Project Status', style: DFTextStyles.screenTitle.copyWith(fontSize: 16, color: DFColors.primaryContainerStitch)),
        ),
        TextButton(
          onPressed: () {},
          child: Text('View All', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }
}

class _ProjectRiskCard extends ConsumerWidget {
  final ProjectModel project;
  const _ProjectRiskCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviationAsync = ref.watch(latestDeviationProvider(project.projectId));

    // Calculate real progress
    final totalDuration = project.expectedEndDate.difference(project.startDate).inDays;
    final elapsed = DateTime.now().difference(project.startDate).inDays;
    final progressVal = (elapsed / totalDuration).clamp(0.0, 1.0);
    final progressPercent = (progressVal * 100).toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GestureDetector(
        onTap: () => context.push('/projects/${project.projectId}'),
        child: Container(
          decoration: BoxDecoration(
            color: DFColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x0F191C1E), blurRadius: 32, offset: Offset(0, 12))],
          ),
          clipBehavior: Clip.hardEdge,
          child: deviationAsync.when(
            data: (devData) {
              final severity = devData?['overallSeverity'] as String? ?? 'normal';
              double prob = (devData?['mlOverrunProbability'] as num? ?? 0.0) * 100;
              
              Color statusColor;
              Color bgPillColor;
              Color textPillColor;
              if (severity == 'critical') {
                statusColor = const Color(0xFF850009);
                bgPillColor = const Color(0xFFB10010);
                textPillColor = Colors.white;
              } else if (severity == 'warning') {
                statusColor = const Color(0xFFFEA619);
                bgPillColor = const Color(0xFFFEA619);
                textPillColor = const Color(0xFF2A1700);
              } else {
                statusColor = const Color(0xFF16A34A);
                bgPillColor = const Color(0xFFDCFCE7);
                textPillColor = const Color(0xFF166534);
                if (prob == 0.0) prob = 4.0;
              }

              return Row(
                children: [
                  Container(width: 6, height: 140, color: statusColor),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(project.name, style: DFTextStyles.screenTitle.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 12, color: DFColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(project.location, style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: bgPillColor, borderRadius: BorderRadius.circular(16)),
                                child: Text(severity.toUpperCase(), style: DFTextStyles.labelSm.copyWith(color: textPillColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Progress ($elapsed / $totalDuration days)', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500)),
                                  Text('$progressPercent%', style: DFTextStyles.labelSm.copyWith(color: DFColors.textPrimary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity, height: 6,
                                decoration: BoxDecoration(color: DFColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft, widthFactor: progressVal,
                                  child: Container(decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4))),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(height: 1, color: DFColors.surfaceContainerLow),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Overrun Probability', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary)),
                                  Row(
                                    children: [
                                      Text('${prob.toInt()}%', style: DFTextStyles.labelSm.copyWith(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                      const SizedBox(width: 8),
                                      Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Padding(padding: EdgeInsets.all(32.0), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16.0), child: Text('ERR: $e', style: DFTextStyles.caption.copyWith(color: DFColors.critical))),
          ),
        ),
      ),
    );
  }
}
