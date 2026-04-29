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
import '../../providers/weather_provider.dart';

class ManagerDashboard extends ConsumerStatefulWidget {
  const ManagerDashboard({super.key});

  @override
  ConsumerState<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends ConsumerState<ManagerDashboard> {
  String? _selectedChartProjectId;



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
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreetingSection(userProfile?.name ?? 'Manager'),
                  const SizedBox(height: 12),
                  _buildWeatherCard(),
                ],
              ),
            ),
          ),
          
          // Layered Summary Sections
          SliverToBoxAdapter(
            child: _buildSummaryCards(projectsAsync.value ?? [], summaryAsync.value ?? {}, avgRisk),
          ),
          
          // =========================================================================
          // 📍 POSITIONING: USAGE TREND SECTION
          // Modify the vertical padding (SizedBox or Padding below) to move this block.
          // =========================================================================
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTrendSection(projectsAsync.value ?? []),
                ],
              ),
            ),
          ),
          // =========================================================================

          // =========================================================================
          // 📍 POSITIONING: PROJECT STATUS SECTION
          // =========================================================================
          projectsAsync.when(
            data: (projects) {
              // --- UI STYLE CONFIGURATION (PROJECT STATUS SECTION) ---
              const double statusSectionTopPadding = 0.0;     // Space above title
              const double statusSectionBottomPadding = 96.0;  // Space below the whole list
              const double horizontalPadding = 24.0;          // Left/Right margins
              const double titleToCardGap = 8.0;              // Space between title and first card
              const double cardSpacing = 3.0;                 // Space between each card

              // SECTION DIVIDER (BETWEEN CHART AND STATUS)
              const Color dividerColor = Color(0x3394A3B8);   // <--- Line color
              const double dividerThickness = 5.0;            // <--- Line thickness
              const double dividerTopPadding = 8.0;          // <--- Space above line
              const double dividerBottomPadding = 10.0;       // <--- Space below line

              // BULLET POINT (PROJECT STATUS HEADER)
              const Color bulletColor = DFColors.primaryStitch; // <--- Bullet color
              const double bulletSize = 8.0;                  // <--- Bullet diameter
              const double bulletToTextGap = 10.0;            // <--- Space after bullet

              // VIEW ALL BUTTON (EXPANSION)
              const double viewAllBtnWidth = 180.0;           // <--- Button Width
              const double viewAllBtnHeight = 40.0;           // <--- Button Height
              const Color viewAllBtnColor = DFColors.primaryStitch;
              const double viewAllBtnRadius = 24.0;
              const double viewAllBtnTextSize = 12.0;         // <--- Button Text Size
              const double viewAllBtnTopGap = 12.0;           // Space above button
              // --------------------------------------------------------

              if (projects.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('No active projects')),
                );
              }

              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding, 
                  statusSectionTopPadding, 
                  horizontalPadding, 
                  statusSectionBottomPadding
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 📏 THE DIVIDER LINE
                    Padding(
                      padding: EdgeInsets.only(top: dividerTopPadding, bottom: dividerBottomPadding),
                      child: Divider(color: dividerColor, thickness: dividerThickness),
                    ),
                    _buildProjectStatusHeader(bulletColor: bulletColor, bulletSize: bulletSize, bulletGap: bulletToTextGap),
                    SizedBox(height: titleToCardGap),
                    
                    // SHOW THE SELECTED PROJECT
                    _ProjectRiskCard(project: projects.firstWhere((p) => p.projectId == _selectedChartProjectId, orElse: () => projects.first)),
                    
                    // THE NEW VIEW ALL BUTTON (Below the Card)
                    if (projects.length > 1)
                      Padding(
                        padding: EdgeInsets.only(top: viewAllBtnTopGap),
                        child: Center(
                          child: InkWell(
                            onTap: () => _showAllProjectsModal(context, projects),
                            borderRadius: BorderRadius.circular(viewAllBtnRadius),
                            child: Container(
                              width: viewAllBtnWidth,
                              height: viewAllBtnHeight,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: viewAllBtnColor,
                                borderRadius: BorderRadius.circular(viewAllBtnRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: viewAllBtnColor.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Text(
                                'VIEW ALL PROJECTS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: viewAllBtnTextSize,
                                  letterSpacing: 0.5,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
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
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DFColors.primaryContainerStitch,
              border: Border.all(color: Colors.white, width: 2),
            ),
            clipBehavior: Clip.hardEdge,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          Text('ConstructIQ', 
            style: DFTextStyles.screenTitle.copyWith(
              color: DFColors.primaryStitch, 
              fontSize: 24, 
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            )
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: DFColors.primaryStitch),
                onPressed: () => context.push('/notifications'),
              ),
              Consumer(
                builder: (context, ref, child) {
                  final allDevsAsync = ref.watch(allDeviationsProvider);
                  final readIds = ref.watch(readNotificationsProvider);
                  
                  bool hasUnread = false;
                  if (allDevsAsync.hasValue) {
                    hasUnread = allDevsAsync.value!.any((d) => !readIds.contains(d['deviationId'] as String? ?? ''));
                  }

                  if (!hasUnread) return const SizedBox.shrink();

                  return Positioned(
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
                  );
                },
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
      ],
    );
  }

  Widget _buildSummaryCards(List<ProjectModel> projects, Map<String, dynamic> summary, double avgRisk) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        children: [
          // LAYER 1: Active Projects & Warnings
          Row(
            children: [
              Expanded(child: _sectionActiveProjects(projects.length)),
              const SizedBox(width: 12),
              Expanded(child: _sectionWarnings(summary['warnings'] ?? 0)),
            ],
          ),
          const SizedBox(height: 10), // Gap between Layer 1 and 2

          // LAYER 2: Critical
          _sectionCritical(summary['criticals'] ?? 0),
          const SizedBox(height: 10), // Gap between Layer 2 and 3

          // LAYER 3: Average Overrun Risk
          _sectionOverrunRisk(avgRisk),
        ],
      ),
    );
  }

  // =========================================================================
  // 🔘 SECTION 1: ACTIVE PROJECTS
  // =========================================================================
  Widget _sectionActiveProjects(int count) {
    // ---- TWEAK ABLE PARAMETERS ----
    const double height = 75.0;
    const Color bgColor = DFColors.primaryContainerStitch;
    const Color textColor = Colors.white;
    const Color shadowColor = Color(0x201A56A0);
    const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    // -------------------------------

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: shadowColor, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('ACTIVE\nPROJECTS', 
              style: DFTextStyles.labelSm.copyWith(color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 10, height: 1.2)),
          ),
          _buildCircle(count.toString(), textColor),
        ],
      ),
    );
  }

  // =========================================================================
  // 🔘 SECTION 2: WARNINGS
  // =========================================================================
  Widget _sectionWarnings(int count) {
    // ---- TWEAK ABLE PARAMETERS ----
    const double height = 75.0;
    const Color bgColor = Color(0xFFFEA619);
    const Color textColor = Color(0xFF2A1700);
    const Color shadowColor = Color(0x20FEA619);
    const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    // -------------------------------

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: shadowColor, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(count == 1 ? 'WARNING' : 'WARNINGS', 
              style: DFTextStyles.labelSm.copyWith(color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 10, height: 1.2)),
          ),
          _buildCircle(count.toString(), textColor),
        ],
      ),
    );
  }

  // =========================================================================
  // 🔘 SECTION 3: CRITICAL (Centered Layer)
  // =========================================================================
  Widget _sectionCritical(int count) {
    // ---- TWEAK ABLE PARAMETERS ----
    const double height = 75.0;
    const int flexWidth = 200; // Higher = wider box
    const int spacerFlex = 1;  // Higher = more side space
    const Color bgColor = Color(0xFFB10010);
    const Color textColor = Colors.white;
    const Color shadowColor = Color(0x20B10010);
    const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    // -------------------------------

    return Row(
      children: [
        Spacer(flex: spacerFlex),
        Expanded(
          flex: flexWidth,
          child: Container(
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: shadowColor, blurRadius: 16, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('CRITICAL', 
                    style: DFTextStyles.labelSm.copyWith(color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 10, height: 1.2)),
                ),
                _buildCircle(count.toString(), textColor),
              ],
            ),
          ),
        ),
        Spacer(flex: spacerFlex),
      ],
    );
  }

  // =========================================================================
  // 🔘 SECTION 4: AVERAGE OVERRUN RISK (Centered Layer, No Circle)
  // =========================================================================
  Widget _sectionOverrunRisk(double avgRisk) {
    // ---- TWEAK ABLE PARAMETERS ----
    const double height = 75.0;
    const int flexWidth = 140; // Higher = wider box
    const int spacerFlex = 1;  // Higher = more side space
    const Color bgColor = DFColors.surface;
    const Color textColor = DFColors.textSecondary;
    const Color valueColor = Color(0xFF855300);
    const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    // -------------------------------

    return Row(
      children: [
        Spacer(flex: spacerFlex),
        Expanded(
          flex: flexWidth,
          child: Container(
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.15)),
              boxShadow: const [BoxShadow(color: Color(0x08191C1E), blurRadius: 16, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('AVG. OVERRUN RISK', 
                    style: DFTextStyles.labelSm.copyWith(color: textColor, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 10, height: 1.2)),
                ),
                Text('${avgRisk.toStringAsFixed(1)}%', 
                  style: DFTextStyles.screenTitle.copyWith(fontSize: 22, color: valueColor, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        Spacer(flex: spacerFlex),
      ],
    );
  }

  // Helper for the number-in-circle design (Used by Sections 1, 2, 3)
  Widget _buildCircle(String value, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(value, style: TextStyle(
        fontSize: 16, 
        color: color, 
        fontWeight: FontWeight.w900,
        fontFamily: 'Inter',
      )),
    );
  }

  Widget _buildTrendSection(List<ProjectModel> projects) {
    if (projects.isEmpty) return const SizedBox();

    // =========================================================================
    // 🎨 UI STYLE CONFIGURATION (TREND SECTION ONLY)
    // =========================================================================
    const double chartContainerHeight = 260.0; // <--- Height of the chart box
    const double titleFontSize = 18.0;         // <--- "Usage Trend" size
    const double subtitleFontSize = 12.0;      // <--- "7-day cumulative..." size
    const double legendFontSize = 11.0;        // <--- "Cement", "Bricks", etc.
    const double chartLabelSize = 10.0;        // <--- Axis number/day size
    
    // Spacing and Padding
    const double overallTopGap = 8.0;          // Gap ABOVE this whole section
    const double headerBottomGap = 12.0;       // Gap below title
    const double legendItemGap = 8.0;          // Gap between legend rows
    const double selectorBottomGap = 18.0;     // <--- Gap below the dropdown
    const EdgeInsets chartPadding = EdgeInsets.fromLTRB(12, 24, 24, 16);

    // Capsule & Circle Selector Styling
    const double selectorHeight = 40.0;       // <--- Height of the duo
    const double capsuleWidth = 190.0;        // <--- Width of the name part
    const double circleSize = 40.0;           // <--- Width/Height of the icon part
    const double gapBetweenParts = 8.0;       // Space between Capsule and Circle
    
    const Color capsuleBgColor = DFColors.surfaceContainerLow;
    const Color capsuleTextColor = DFColors.textPrimary;
    const Color capsuleBorderColor = DFColors.primaryStitch; // <--- Capsule border
    const Color circleBgColor = DFColors.primaryStitch;     // <--- Circle color
    const Color circleIconColor = Colors.white;             // <--- Icon color
    
    const double dropdownTextSize = 13.0;
    const double capsuleRadius = 12.0;        // <--- Corner roundness
    const double capsulePadding = 16.0;       // <--- Side spacing for text
    const Alignment capsuleAlignment = Alignment.center; // <--- Tweak text position
    // =========================================================================
    
    _selectedChartProjectId ??= projects.first.projectId;
    
    final logsAsync = ref.watch(resourceLogsProvider(_selectedChartProjectId!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: overallTopGap), // Independent top gap
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Usage Trend', 
                      style: TextStyle(
                        fontSize: titleFontSize, 
                        color: DFColors.textPrimary, 
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Inter',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('7-day cumulative consumption', 
                      style: TextStyle(
                        fontSize: subtitleFontSize, 
                        color: DFColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Layered Style Legend (1, 2, 3)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildLegendItem(label: 'Cement', color: const Color(0xFFFEA619), fontSize: legendFontSize),
                SizedBox(height: legendItemGap),
                _buildLegendItem(label: 'Bricks', color: const Color(0xFF5C6BC0), fontSize: legendFontSize),
                SizedBox(height: legendItemGap),
                _buildLegendItem(label: 'Steel', color: const Color(0xFF26A69A), fontSize: legendFontSize),
              ],
            ),
          ],
        ),
        const SizedBox(height: headerBottomGap),

        // NEW: Split-Design Selector (Capsule + Circle)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedChartProjectId,
                icon: const SizedBox.shrink(), // Hiding default icon
                dropdownColor: DFColors.surface,
                borderRadius: BorderRadius.circular(capsuleRadius),
                // This builds the custom "Button" look (Capsule on left, Circle on right)
                selectedItemBuilder: (BuildContext context) {
                  return projects.map<Widget>((p) {
                    return Row(
                      children: [
                        // THE CAPSULE (Left Part)
                        Container(
                          width: capsuleWidth,
                          height: selectorHeight,
                          padding: EdgeInsets.symmetric(horizontal: capsulePadding),
                          decoration: BoxDecoration(
                            color: capsuleBgColor,
                            borderRadius: BorderRadius.circular(capsuleRadius),
                            border: Border.all(color: capsuleBorderColor, width: 1.0),
                          ),
                          alignment: capsuleAlignment,
                          child: Text(
                            p.name,
                            style: TextStyle(
                              color: capsuleTextColor,
                              fontSize: dropdownTextSize,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: gapBetweenParts),
                        // THE CIRCLE (Right Part)
                        Container(
                          width: circleSize,
                          height: circleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: circleBgColor,
                            boxShadow: [
                              BoxShadow(
                                color: circleBgColor.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Icon(Icons.keyboard_arrow_down_rounded, color: circleIconColor, size: 24),
                        ),
                      ],
                    );
                  }).toList();
                },
                items: projects.map((p) => DropdownMenuItem(
                  value: p.projectId,
                  child: Text(p.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500)),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedChartProjectId = val;
                    });
                  }
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: selectorBottomGap),
        Container(
          height: chartContainerHeight,
          padding: chartPadding,
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
                                  style: TextStyle(color: DFColors.textSecondary, fontSize: chartLabelSize, fontFamily: 'Inter')
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
                                    style: TextStyle(
                                      color: DFColors.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: chartLabelSize,
                                      fontFamily: 'Inter',
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

  Widget _buildLegendItem({required String label, required Color color, bool isDashed = false, double fontSize = 11.0}) {
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
        Text(label, style: TextStyle(
          color: DFColors.textSecondary, 
          fontWeight: FontWeight.w500, 
          fontSize: fontSize,
          fontFamily: 'Inter',
        )),
      ],
    );
  }

  Widget _buildProjectStatusHeader({required Color bulletColor, required double bulletSize, required double bulletGap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: bulletSize,
              height: bulletSize,
              decoration: BoxDecoration(
                color: bulletColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: bulletGap),
            Text('Project Status', style: DFTextStyles.screenTitle.copyWith(fontSize: 16, color: DFColors.primaryContainerStitch)),
          ],
        ),
        // "View All" button removed from header (moved below project card)
      ],
    );
  }

  void _showAllProjectsModal(BuildContext context, List<ProjectModel> projects) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, controller) {
        // --- UI STYLE CONFIGURATION (MINI-SCREEN MODAL) ---
        const double modalTitleTopPadding = 24.0;    // Space above title
        const double modalTitleBottomPadding = 8.0; // Space below title
        const double listBottomGap = 10.0;           // Space below last card
        
        const Color modalBulletColor = DFColors.primaryStitch;
        const double modalBulletSize = 8.0;
        const double modalBulletGap = 10.0;
        
        const Color closeBtnBgColor = DFColors.surfaceContainerLow;
        const Color closeIconColor = DFColors.textPrimary;
        // --------------------------------------------------

        return Container(
          decoration: const BoxDecoration(
            color: DFColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [

              // Modal Indicator
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: DFColors.outlineVariant, borderRadius: BorderRadius.circular(2))),
              
              Padding(
                padding: EdgeInsets.fromLTRB(24, modalTitleTopPadding, 24, modalTitleBottomPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: modalBulletSize,
                          height: modalBulletSize,
                          decoration: BoxDecoration(color: modalBulletColor, shape: BoxShape.circle),
                        ),
                        SizedBox(width: modalBulletGap),
                        const Text('All Projects', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
                      ],
                    ),
                    // Premium Circular Close Button
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: closeBtnBgColor, shape: BoxShape.circle),
                        child: Icon(Icons.close, size: 20, color: closeIconColor),
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(24, 8, 24, listBottomGap),
                  itemCount: projects.length,
                  itemBuilder: (context, index) => _ProjectRiskCard(project: projects[index]),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
  // ═══════════════════════════════════════════════════════════════
  // 🌤️ WEATHER & SITE CONDITIONS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildWeatherCard() {
    final weatherAsync = ref.watch(dashboardWeatherProvider);

    return weatherAsync.when(
      data: (weather) {
        if (weather == null) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A56A0), Color(0xFF2D7DD2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A56A0).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SITE CONDITIONS',
                        style: DFTextStyles.labelSm.copyWith(color: Colors.white70, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        weather.condition,
                        style: DFTextStyles.screenTitle.copyWith(color: Colors.white, fontSize: 20),
                      ),
                    ],
                  ),
                  Icon(
                    _getWeatherIcon(weather.weatherCode),
                    color: Colors.white,
                    size: 40,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _weatherStat('Temp', '${weather.temperature}°C', Icons.thermostat),
                  _weatherStat('Humidity', '${weather.humidity}%', Icons.water_drop),
                  _weatherStat('Wind', '${weather.windSpeed} km/h', Icons.air),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _weatherStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code <= 3) return Icons.wb_cloudy_rounded;
    if (code <= 48) return Icons.cloud_rounded;
    if (code <= 67) return Icons.umbrella_rounded;
    if (code <= 77) return Icons.ac_unit_rounded;
    if (code <= 82) return Icons.umbrella_rounded;
    if (code <= 99) return Icons.thunderstorm_rounded;
    return Icons.cloud_rounded;
  }
}

class _ProjectRiskCard extends ConsumerWidget {
  final ProjectModel project;
  const _ProjectRiskCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviationAsync = ref.watch(latestDeviationProvider(project.projectId));

    // Calculate real progress
    final totalDuration = project.durationDays > 0 
        ? project.durationDays 
        : project.expectedEndDate.difference(project.startDate).inDays;
    
    final now = DateTime.now();
    final start = project.startDate;
    final elapsed = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
        
    final progressVal = (elapsed / (totalDuration > 0 ? totalDuration : 365)).clamp(0.0, 1.0);
    final currentDayDisplay = (elapsed + 1).clamp(1, totalDuration > 0 ? totalDuration : 1);
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
                                    const SizedBox(height: 4),
                                    Consumer(
                                      builder: (context, ref, child) {
                                        final creatorAsync = ref.watch(userByIdProvider(project.createdBy));
                                        return creatorAsync.when(
                                          data: (user) => Text(
                                            'Managed by: ${user?.name ?? "Loading..."}', 
                                            style: DFTextStyles.caption.copyWith(fontSize: 10, color: DFColors.primaryStitch, fontWeight: FontWeight.bold)
                                          ),
                                          loading: () => const Text('Loading manager...', style: TextStyle(fontSize: 10)),
                                          error: (_, __) => const SizedBox.shrink(),
                                        );
                                      }
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
                                  Text('Progress ($currentDayDisplay / $totalDuration days)', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500)),
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
