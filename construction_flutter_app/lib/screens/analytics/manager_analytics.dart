import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/design_tokens.dart';
import '../../models/project_model.dart';

import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../providers/ml_provider.dart';
import '../../models/resource_log_model.dart';
import '../../models/deviation_model.dart';
import '../../providers/ml_cache_provider.dart';


class ManagerAnalytics extends ConsumerStatefulWidget {
  const ManagerAnalytics({super.key});

  @override
  ConsumerState<ManagerAnalytics> createState() => _ManagerAnalyticsState();
}

class _ManagerAnalyticsState extends ConsumerState<ManagerAnalytics> {
  String? _selectedProjectId;
  String _selectedMaterial = 'cement';
  final List<String> _materialKeys = ['cement', 'bricks', 'steel', 'sand', 'aggregate'];

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        centerTitle: false,
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
            Text(
              'Project Analytics',
              style: DFTextStyles.screenTitle.copyWith(
                color: DFColors.primaryStitch,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: DFColors.primaryStitch),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: DFSpacing.sm),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(child: Text('No projects found'));
          }
          // Auto-select the first project if none selected
          if (_selectedProjectId == null || !projects.any((p) => p.projectId == _selectedProjectId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedProjectId = projects.first.projectId);
            });
            return const Center(child: CircularProgressIndicator(color: DFColors.primary));
          }

          final selectedProject = projects.firstWhere((p) => p.projectId == _selectedProjectId);
          return _buildContent(context, projects, selectedProject);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primary)),
        error: (e, _) => Center(child: Text('Error loading projects: $e')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ProjectModel> projects, ProjectModel selectedProject) {
    final cacheState = ref.watch(mlCacheProvider);
    final cachedResult = cacheState.results[_selectedProjectId!];

    final deviationAsync = cachedResult != null
        ? AsyncValue.data(cachedResult)
        : ref.watch(latestDeviationProvider(_selectedProjectId!));

    final logsAsync = ref.watch(projectLogsProvider(_selectedProjectId!));

    // Cache the newly computed value if it resolved successfully and is not yet cached
    if (cachedResult == null && deviationAsync.hasValue) {
      final dev = deviationAsync.value!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(mlCacheProvider.notifier).setResult(
          _selectedProjectId!,
          dev.mlOverrunProbability,
          dev.overallSeverity,
          dev,
        );
      });
    }

    final deviation = deviationAsync.valueOrNull;
    final logs = logsAsync.valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg, vertical: DFSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Context Header with Selector
          _buildProjectContextHeader(context, projects, selectedProject, deviation, logs),
          const SizedBox(height: DFSpacing.md),

          // 1. Material Usage Trend (from resource logs)
          _buildMaterialUsageTrend(),
          const SizedBox(height: DFSpacing.md),

          // 2. Deviation Severity (from deviation data)
          deviationAsync.when(
            data: (devData) => _buildDeviationSeverity(devData),
            loading: () => _buildShimmerCard(200),
            error: (_, __) => _buildDeviationSeverity(null),
          ),
          const SizedBox(height: DFSpacing.md),

          // 3. Equipment Utilisation (from resource logs)
          _buildEquipmentUtilisation(),
          const SizedBox(height: DFSpacing.md),

          // 4. Report Generation Card
          _buildReportGenerationCard(context),
          const SizedBox(height: DFSpacing.lg),
        ],
      ),
    );
  }

  // ── Project Context Header with Dropdown ──
  Widget _buildProjectContextHeader(
    BuildContext context,
    List<ProjectModel> projects,
    ProjectModel selected,
    DeviationResult? deviation,
    List<ResourceLogModel>? logs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVE PROJECT', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: DFColors.textSecondary)),
        const SizedBox(height: 4),
        // Project Selector Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedProjectId,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
              style: DFTextStyles.screenTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
              items: projects.map((p) => DropdownMenuItem(value: p.projectId, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedProjectId = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 13, color: DFColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                selected.location.trim().replaceAll(RegExp(r',\s*$'), ''),
                style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: DFColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: DFSpacing.md),
        Center(
          child: _buildHeaderButton('View Insights', Icons.insights, true, () {
            if (deviation != null) {
              _showInsightsBottomSheet(context, selected, deviation, logs);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Deviation analysis is currently loading or unavailable.'),
                  backgroundColor: Color(0xFFFEA619),
                ),
              );
            }
          }),
        ),
      ],
    );
  }

  Widget _buildHeaderButton(String label, IconData icon, bool isPrimary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? DFColors.primary : DFColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isPrimary ? [BoxShadow(color: DFColors.primary.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPrimary) ...[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(label, style: DFTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : const Color(0xFF00468C),
            )),
          ],
        ),
      ),
    );
  }

  // ── 1. Material Usage Trend (Dynamic from resource logs) ──
  Widget _buildMaterialUsageTrend() {
    if (_selectedProjectId == null) return _buildShimmerCard(200);

    final logsAsync = ref.watch(projectLogsProvider(_selectedProjectId!));

    return logsAsync.when(
      data: (logs) {
        // Extract latest 7 logs (first 7 in descending list) and reverse for chronological display
        final displayLogs = logs.take(7).toList().reversed.toList();
        final dataPoints = <double>[];
        
        for (var log in displayLogs) {
          final mats = log.materialUsage;
          final val = (mats[_selectedMaterial] as num? ?? 
                       mats['${_selectedMaterial}_bags'] as num? ?? 
                       mats['${_selectedMaterial}_kg'] as num? ?? 
                       mats['${_selectedMaterial}_m3'] as num? ?? 
                       0.0).toDouble();
          dataPoints.add(val);
        }

        // Get estimated value from breakdown if available
        double? estimatedDaily;
        if (dataPoints.isNotEmpty) {
          estimatedDaily = dataPoints.reduce((a, b) => a + b) / dataPoints.length;
        }

        return Container(
          padding: const EdgeInsets.all(DFSpacing.lg),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.06), blurRadius: 32, offset: Offset(0, 12))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Material Usage Trend', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
                        const SizedBox(height: 2),
                        Text('Daily consumption (last 7 logs)', style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary)),
                      ],
                    ),
                  ),
                  // Summary badge
                  if (dataPoints.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                      child: Text('${dataPoints.length} logs', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: DFColors.primary)),
                    ),
                ],
              ),
              const SizedBox(height: DFSpacing.md),
              // Interactive Material Selector Toggles
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _materialKeys.map((key) => _buildMaterialChip(key, key == _selectedMaterial)).toList(),
              ),
              const SizedBox(height: DFSpacing.lg),
              // Chart area
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
                ),
                child: dataPoints.isEmpty
                    ? Center(child: Text('No resource logs available', style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary)))
                    : CustomPaint(
                        size: const Size(double.infinity, 200),
                        painter: _DynamicChartPainter(dataPoints: dataPoints, estimatedValue: estimatedDaily),
                      ),
              ),
              const SizedBox(height: DFSpacing.sm),
              // X-axis labels from log dates
              if (logs.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatLogDate(logs.first), style: DFTextStyles.caption.copyWith(fontSize: 9, color: DFColors.textSecondary)),
                    Text('Latest', style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: DFColors.primary)),
                  ],
                ),
            ],
          ),
        );
      },
      error: (Object err, StackTrace? stack) => Center(child: Text('Error: $err')),
      loading: () => _buildShimmerCard(200),
    );
  }

  String _formatLogDate(ResourceLogModel log) {
    final d = log.date;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  Widget _buildMaterialChip(String label, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _selectedMaterial = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? DFColors.primaryFixed : DFColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? DFColors.primary : DFColors.outline)),
            const SizedBox(width: 8),
            Text(label[0].toUpperCase() + label.substring(1), style: DFTextStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? DFColors.textPrimary : DFColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── 2. Deviation Severity (Dynamic from deviation data) ──
  Widget _buildDeviationSeverity(DeviationResult? devData) {
    final perMaterial = devData?.perMaterial ?? {};
    final overallSeverity = devData?.overallSeverity ?? 'normal';
    final mlProb = devData?.mlOverrunProbability ?? 0.0;

    // Extract material deviations (Ensure Cement, Bricks, Steel always show)
    final materialDevs = <String, double>{};
    double totalDev = 0;
    int count = 0;
    
    // Core materials that must always be visible
    final coreMaterials = ['cement', 'bricks', 'steel'];
    
    for (var key in coreMaterials) {
      final data = perMaterial[key];
      final pct = data?.deviationPct ?? 0.0;
      materialDevs[key] = pct;
      totalDev += pct.abs();
      count++;
    }
    
    // Additional materials only if they have data
    for (var key in ['sand', 'aggregate']) {
      if (perMaterial.containsKey(key)) {
        final data = perMaterial[key];
        final pct = data?.deviationPct ?? 0.0;
        materialDevs[key] = pct;
        totalDev += pct.abs();
        count++;
      }
    }
    final avgDev = count > 0 ? totalDev / count : 0.0;

    // Bar colors based on deviation level
    Color barColor(double pct) {
      if (pct.abs() > 30) return const Color(0xFFB10010);
      if (pct.abs() > 15) return DFColors.secondaryContainer;
      return DFColors.surfaceContainerHigh;
    }

    return Container(
      padding: const EdgeInsets.all(DFSpacing.lg),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.06), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Deviation Severity', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: overallSeverity == 'critical' ? const Color(0xFFB10010) : overallSeverity == 'warning' ? DFColors.secondaryContainer : DFColors.normal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(overallSeverity.toUpperCase(), style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Material variance from estimates', style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary)),
          const SizedBox(height: DFSpacing.xl),
          // Bar chart
          if (materialDevs.isEmpty)
            SizedBox(height: 120, child: Center(child: Text('No deviation data', style: DFTextStyles.caption)))
          else
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: materialDevs.entries.map((e) {
                  final heightFactor = (e.value.abs() / 100).clamp(0.05, 1.0);
                  return _buildBar(e.key[0].toUpperCase() + e.key.substring(1, (e.key.length > 3 ? 3 : e.key.length)), heightFactor, barColor(e.value), '${e.value > 0 ? "+" : ""}${e.value.toStringAsFixed(1)}%');
                }).toList(),
              ),
            ),
          const SizedBox(height: DFSpacing.lg),
          // Average Deviation + ML Probability
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Average Deviation', style: DFTextStyles.caption.copyWith(fontSize: 12, color: DFColors.textSecondary)),
              Text('${avgDev.toStringAsFixed(1)}%', style: DFTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.bold, color: DFColors.secondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (avgDev / 50).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: DFColors.surfaceContainerLow,
              color: DFColors.secondary,
            ),
          ),
          const SizedBox(height: DFSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ML Overrun Probability', style: DFTextStyles.caption.copyWith(fontSize: 12, color: DFColors.textSecondary)),
              Text('${(mlProb * 100).toStringAsFixed(0)}%', style: DFTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.bold, color: mlProb > 0.5 ? DFColors.critical : DFColors.normal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double heightFactor, Color color, String tooltip) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(tooltip, style: DFTextStyles.caption.copyWith(fontSize: 8, fontWeight: FontWeight.bold, color: DFColors.textSecondary)),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── 3. Equipment Utilisation (Dynamic from resource logs) ──
  Widget _buildEquipmentUtilisation() {
    if (_selectedProjectId == null) return const SizedBox.shrink();
    
    final logsAsync = ref.watch(projectLogsProvider(_selectedProjectId!));

    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(DFSpacing.lg),
            decoration: BoxDecoration(
              color: DFColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.06), blurRadius: 32, offset: Offset(0, 12))],
            ),
            child: const Center(child: Text('No equipment data available')),
          );
        }

        // Get equipment from latest log
        final latestLog = logs.first;
        final equipment = latestLog.equipmentList;

        return Container(
          padding: const EdgeInsets.all(DFSpacing.lg),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.06), blurRadius: 32, offset: Offset(0, 12))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.construction, size: 18, color: DFColors.primaryContainer),
                      const SizedBox(width: 8),
                      Text('Equipment Utilisation', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
                    ],
                  ),
                  Row(
                    children: [
                      _legendDot('Used', DFColors.primaryContainer),
                      const SizedBox(width: DFSpacing.md),
                      _legendDot('Idle', DFColors.secondaryContainer),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: DFSpacing.xl),
              if (equipment.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DFSpacing.lg),
                  child: Center(child: Text('No equipment reported in latest log', style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary))),
                )
              else
                ...equipment.map((entry) {
                  final name = entry.name;
                  final hoursUsed = entry.usedHours;
                  final hoursIdle = entry.idleHours;
                  final total = hoursUsed + hoursIdle;
                  final usedPercent = total > 0 ? hoursUsed / total : 0.0;
                  final idlePercent = total > 0 ? (hoursIdle / total * 100).round() : 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: DFSpacing.lg),
                    child: _buildEquipmentRow(name, usedPercent, '${hoursUsed.toStringAsFixed(0)} hrs', '$idlePercent% Idle',
                      idlePercent > 30 ? DFColors.critical : DFColors.textSecondary),
                  );
                }),
            ],
          ),
        );
      },
      error: (Object err, StackTrace? stack) => Center(child: Text('Error: $err')),
      loading: () => _buildShimmerCard(200),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label, style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildEquipmentRow(String name, double usedPercent, String hours, String idleText, Color idleColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(idleText, style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: idleColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  flex: (usedPercent * 100).toInt().clamp(1, 100),
                  child: Container(
                    color: DFColors.primaryContainer,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(hours, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w500)),
                  ),
                ),
                if ((1 - usedPercent) > 0)
                  Expanded(
                    flex: ((1 - usedPercent) * 100).toInt().clamp(1, 100),
                    child: Container(color: DFColors.secondaryContainer.withValues(alpha: 0.3)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 4. Report Generation Card ──
  Widget _buildReportGenerationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DFSpacing.lg),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: const Border(top: BorderSide(color: DFColors.primary, width: 4)),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(25, 28, 30, 0.06), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generate Project Report', style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: DFColors.primaryContainer)),
          const SizedBox(height: 4),
          Text('For the selected project', style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary)),
          const SizedBox(height: DFSpacing.xl),
          Text('REPORT TYPE', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: DFColors.textSecondary)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: DFColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Full Material & Efficiency Audit', style: DFTextStyles.body.copyWith(fontSize: 13)),
          ),
          const SizedBox(height: DFSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _selectedProjectId != null ? () => context.push('/projects/$_selectedProjectId/pdf-preview') : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DFColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: DFColors.primary.withValues(alpha: 0.2),
              ),
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              label: Text('Generate PDF Report', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(height: DFSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assessment, size: 14, color: DFColors.textSecondary),
              const SizedBox(width: 6),
              Text('Auto-sync enabled for enterprise storage', style: DFTextStyles.caption.copyWith(fontSize: 10, color: DFColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  void _showInsightsBottomSheet(
    BuildContext context,
    ProjectModel project,
    DeviationResult deviation,
    List<ResourceLogModel>? logs,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String sheetSelectedMaterial = 'cement';
        return StatefulBuilder(
          builder: (context, setSheetState) {
        // Calculate ML inputs inside bottom sheet for explanation
        // 1. materialDeviationAvg (f0)
        double sumPct = 0.0;
        int matCount = 0;
        deviation.perMaterial.forEach((key, matDev) {
          sumPct += matDev.deviationPct;
          matCount++;
        });
        double materialDeviationAvg = matCount > 0 ? (sumPct / matCount) : 0.0;

        // 2. equipmentIdleRatio (f1)
        double totalUsed = 0.0;
        double totalIdle = 0.0;
        if (logs != null) {
          for (var log in logs) {
            for (var eq in log.equipmentList) {
              totalUsed += eq.usedHours;
              totalIdle += eq.idleHours;
            }
          }
        }
        double equipmentIdleRatio = (totalUsed + totalIdle) > 0 ? totalIdle / (totalUsed + totalIdle) : 0.0;

        // 3. daysElapsedPct (f2)
        double daysElapsedPct = calculateDaysElapsedPct(project.startDate, project.expectedEndDate);

        // 4. budgetSize (f3)
        double budgetSize = project.plannedBudget;

        // 5. projectTypeEncoded (f4)
        int projectTypeEncoded = encodeProjectType(project.projectType);

        final mlProb = deviation.mlOverrunProbability;
        final severity = deviation.overallSeverity;

        // Premium color mapping matching the ConstructIQ styling
        Color severityColor;
        Color severityBg;
        IconData severityIcon;
        String severityTitle;

        switch (severity.toLowerCase()) {
          case 'critical':
            severityColor = DFColors.critical;
            severityBg = DFColors.criticalBg;
            severityIcon = Icons.report_problem;
            severityTitle = 'CRITICAL OVERRUN RISK';
            break;
          case 'warning':
            severityColor = DFColors.warning;
            severityBg = DFColors.warningBg;
            severityIcon = Icons.warning_amber;
            severityTitle = 'WARNING RISK ALERT';
            break;
          case 'caution':
            severityColor = DFColors.warning;
            severityBg = DFColors.warningBg;
            severityIcon = Icons.info_outline;
            severityTitle = 'CAUTIONARY VARIANCE';
            break;
          default:
            severityColor = DFColors.normal;
            severityBg = DFColors.normalBg;
            severityIcon = Icons.check_circle;
            severityTitle = 'LOW OVERRUN RISK';
        }

        return Container(
          decoration: const BoxDecoration(
            color: DFColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                  const SizedBox(height: 12),
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: DFColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Deviation Intelligence Insights',
                                style: DFTextStyles.headline.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: DFColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ConstructIQ Pattern Analyzer Engine',
                                style: DFTextStyles.caption.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: DFColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: DFColors.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 20, color: DFColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  const Divider(color: DFColors.divider, height: 1),
                  
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        // Engine Architecture Banner
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [DFColors.primary, DFColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: DFColors.primary.withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.memory, color: Colors.white, size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'XGBoost Cost Overrun Classifier',
                                      overflow: TextOverflow.ellipsis,
                                      style: DFTextStyles.body.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF4ADE80),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'ON-DEVICE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'On-device neural-tree inference engine utilizing gradient-boosted decision nodes to parse multi-dimensional site logs. Identifies co-dependent consumption variances, mechanical idle co-variance, and elapsed timeline multipliers to dynamically isolate cost overrun risks.',
                                style: DFTextStyles.body.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Model AUC: 0.82',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Offline Inference: 100% Secure',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Risk Severity and Probability Row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: severityBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: severityColor.withValues(alpha: 0.3), width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(severityIcon, color: severityColor, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'RISK STATE',
                                          style: DFTextStyles.caption.copyWith(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: severityColor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      severityTitle,
                                      style: DFTextStyles.cardTitle.copyWith(
                                        color: severityColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: DFColors.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'OVERRUN PROB.',
                                      style: DFTextStyles.caption.copyWith(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        color: DFColors.textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${(mlProb * 100).toStringAsFixed(1)}%',
                                      style: DFTextStyles.headline.copyWith(
                                        color: mlProb > 0.5 ? DFColors.critical : DFColors.primary,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Defensible Insights Callout Box
                        Container(
                          decoration: BoxDecoration(
                            color: DFColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(left: BorderSide(color: severityColor, width: 4)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color.fromRGBO(25, 28, 30, 0.04),
                                blurRadius: 16,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.lightbulb_outline, color: severityColor, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'AI Pattern Synthesis',
                                    style: DFTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: DFColors.primaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                deviation.aiInsightSummary,
                                style: DFTextStyles.body.copyWith(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: DFColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 28),
                        
                        _buildTrendAnalysisSection(
                          logs,
                          project,
                          sheetSelectedMaterial,
                          (newMat) {
                            setSheetState(() {
                              sheetSelectedMaterial = newMat;
                            });
                          },
                        ),
                        
                        const SizedBox(height: 28),
                        
                        // Feature Pattern Grid Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'AI ANALYSIS FEATURES (5 KEY METRICS)',
                              style: DFTextStyles.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: DFColors.textSecondary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: DFColors.primaryFixed,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Impact Rank',
                                style: DFTextStyles.caption.copyWith(fontSize: 8, fontWeight: FontWeight.bold, color: DFColors.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // 1. Material Deviation
                        _buildFeatureCard(
                          code: 'f0',
                          name: 'Material Deviation Avg',
                          value: '${materialDeviationAvg > 0 ? "+" : ""}${materialDeviationAvg.toStringAsFixed(1)}%',
                          progressValue: (materialDeviationAvg.abs() / 50.0).clamp(0.0, 1.0),
                          explanation: 'The average percentage difference between the actual materials used on site and the planned quantities from the blueprint.',
                          patternImpact: 'Site Impact: A deviation of ${materialDeviationAvg.toStringAsFixed(1)}% indicates that materials are being consumed significantly faster than planned. This consistent overconsumption across key materials points to either high construction waste or underestimated requirements, raising budget risks.',
                          isWarning: materialDeviationAvg > 15.0,
                        ),
                        
                        // 2. Equipment Idle Ratio
                        _buildFeatureCard(
                          code: 'f1',
                          name: 'Equipment Idle Ratio',
                          value: '${(equipmentIdleRatio * 100).toStringAsFixed(1)}%',
                          progressValue: equipmentIdleRatio,
                          explanation: 'The proportion of time heavy machinery (like excavators or concrete mixers) remains inactive relative to their total scheduled operating hours.',
                          patternImpact: 'Site Impact: An idle ratio of ${(equipmentIdleRatio * 100).toStringAsFixed(1)}% indicates underutilized machinery. This usually points to supply delivery delays, coordination issues, or staging bottlenecks. High idle times combined with project delays can compound operational costs significantly.',
                          isWarning: equipmentIdleRatio > 0.3,
                        ),
                        
                        // 3. Days Elapsed Pct
                        _buildFeatureCard(
                          code: 'f2',
                          name: 'Project Timeline Elapsed',
                          value: '${(daysElapsedPct * 100).toStringAsFixed(1)}%',
                          progressValue: daysElapsedPct,
                          explanation: 'Percentage of the total planned project duration that has passed since the start date.',
                          patternImpact: 'Site Impact: The project is ${(daysElapsedPct * 100).toStringAsFixed(1)}% through its timeline. Deviations in early stages have a high risk of compounding over time, making early intervention critical to keep the project on track and within budget.',
                          isWarning: false,
                        ),
                        
                        // 4. Budget Size
                        _buildFeatureCard(
                          code: 'f3',
                          name: 'Project Budget Scale',
                          value: '${budgetSize.toStringAsFixed(1)} Lakhs',
                          progressValue: (budgetSize / 150.0).clamp(0.1, 1.0),
                          explanation: 'Planned contract budget in Indian Rupees (Lakhs), establishing the absolute scale of financial risk.',
                          patternImpact: 'Site Impact: With a budget of ${budgetSize.toStringAsFixed(1)} Lakhs, even minor percentage deviations in material consumption translate to large absolute financial losses, requiring strict inventory and wastage control.',
                          isWarning: false,
                        ),
                        
                        // 5. Project Type
                        _buildFeatureCard(
                          code: 'f4',
                          name: 'Project Classification',
                          value: project.projectType,
                          progressValue: (projectTypeEncoded + 1) / 3.0,
                          explanation: 'Categorized project domain: Residential, Commercial, or Infrastructure. Used to assign historical risk baselines.',
                          patternImpact: 'Site Impact: ${project.projectType} projects have distinct historical usage patterns and tolerance limits. The analysis applies baseline parameters specific to this classification to assess whether the current deviation is typical or anomalous.',
                          isWarning: false,
                        ),
                        
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
        },
      );
    },
  );
}

  Widget _buildFeatureCard({
    required String code,
    required String name,
    required String value,
    required double progressValue,
    required String explanation,
    required String patternImpact,
    required bool isWarning,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWarning ? DFColors.critical.withValues(alpha: 0.2) : DFColors.outlineVariant.withValues(alpha: 0.2),
          width: isWarning ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isWarning ? DFColors.criticalBg : DFColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isWarning ? DFColors.critical : DFColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: DFTextStyles.body.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: isWarning ? DFColors.critical : DFColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 6,
              backgroundColor: DFColors.surfaceContainerLow,
              color: isWarning ? DFColors.critical : DFColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            explanation,
            style: DFTextStyles.caption.copyWith(
              fontSize: 11,
              color: DFColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DFColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 14,
                  color: isWarning ? DFColors.critical : DFColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    patternImpact,
                    style: DFTextStyles.caption.copyWith(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: DFColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendAnalysisSection(
    List<ResourceLogModel>? logs,
    ProjectModel project,
    String selectedLogMaterial,
    void Function(String) onSelectMaterial,
  ) {
    if (logs == null || logs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DFColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: DFColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Daily Log Trend Analysis Proof',
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No execution logs logged yet to establish a daily consumption trend. Once daily activity logs are submitted, the engine will perform sequential trend analysis here.',
              style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Extract latest 7 logs (first 7 in descending list) and reverse for chronological display
    final displayLogs = logs.take(7).toList().reversed.toList();
    
    // Five core materials
    final List<String> materialsToAnalyze = ['cement', 'bricks', 'steel', 'sand', 'aggregate'];
    final Map<String, List<double>> multiMaterialData = {};
    final Map<String, double> materialMeans = {};
    final Map<String, double> materialStdDevs = {};
    final Map<String, String> trendDirections = {};

    for (var mat in materialsToAnalyze) {
      List<double> points = [];
      for (var log in displayLogs) {
        final mats = log.materialUsage;
        final val = (mats[mat] ?? 
                     mats['${mat}_bags'] ?? 
                     mats['${mat}_kg'] ?? 
                     mats['${mat}_m3'] ?? 
                     mats['${mat}_nos'] ?? 
                     0.0).toDouble();
        points.add(val);
      }
      multiMaterialData[mat] = points;

      // Calculate mean
      double mean = 0.0;
      if (points.isNotEmpty) {
        mean = points.reduce((a, b) => a + b) / points.length;
      }
      materialMeans[mat] = mean;

      // Calculate standard deviation
      double variance = 0.0;
      if (points.length > 1) {
        double sqDiffSum = 0.0;
        for (var val in points) {
          sqDiffSum += (val - mean) * (val - mean);
        }
        variance = sqDiffSum / points.length;
      }
      materialStdDevs[mat] = math.sqrt(variance);

      // Determine individual trend directions
      String direction = "Stable";
      if (points.length >= 2) {
        double firstHalf = points.sublist(0, (points.length / 2).floor()).reduce((a, b) => a + b);
        double secondHalf = points.sublist((points.length / 2).floor()).reduce((a, b) => a + b);
        if (secondHalf > firstHalf * 1.05) {
          direction = "Upward";
        } else if (secondHalf < firstHalf * 0.95) {
          direction = "Downward";
        }
      }
      trendDirections[mat] = direction;
    }

    final Map<String, Color> materialColors = {
      'cement': const Color(0xFF3B82F6), // Vibrant Blue
      'bricks': const Color(0xFFEF4444), // Deep Terracotta Red
      'steel': const Color(0xFF8B5CF6),  // Sleek Purple
      'sand': const Color(0xFFF59E0B),   // Warm Amber
      'aggregate': const Color(0xFF10B981), // Emerald Green
    };

    // Equipment info for co-dependency analysis
    double totalUsed = 0.0;
    double totalIdle = 0.0;
    for (var log in displayLogs) {
      for (var eq in log.equipmentList) {
        totalUsed += eq.usedHours;
        totalIdle += eq.idleHours;
      }
    }
    double equipmentIdleRatio = (totalUsed + totalIdle) > 0 ? totalIdle / (totalUsed + totalIdle) : 0.0;

    // Get current daily log values for the interactive selector
    final selectedDailyLogs = multiMaterialData[selectedLogMaterial] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(25, 28, 30, 0.04),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: DFColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '7-Day Micro-Trend & Baseline Variance Proof',
                  style: DFTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: DFColors.primaryContainer,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildMetricChip('ANALYZED MATERIALS', '5 CORE ITEMS', DFColors.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricChip(
                  'ENGINE ANALYSIS', 
                  'Multi-Material Variance', 
                  DFColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal Premium Legend
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: materialsToAnalyze.map((mat) {
              final color = materialColors[mat]!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${mat[0].toUpperCase()}${mat.substring(1)}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Trend Visual Proof (Dashed baseline vs. Solid actual logs)
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: DFColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(double.infinity, 140),
                    painter: _MultiMaterialTrendPainter(
                      multiMaterialData: multiMaterialData,
                      materialMeans: materialMeans,
                      materialColors: materialColors,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DFColors.surfaceContainerHigh.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Dynamic Fluctuation (Solid) vs. Shared Baseline Mean (Center Dashed)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: DFColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Data log timeline display with local material interactive selector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DFColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'DAILY LOG VALUES (Last ${selectedDailyLogs.length} logs):',
                        style: DFTextStyles.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          color: DFColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mini tab indicator selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: DFColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: materialsToAnalyze.map((mat) {
                          final isSel = selectedLogMaterial == mat;
                          return GestureDetector(
                            onTap: () => onSelectMaterial(mat),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSel ? DFColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                mat[0].toUpperCase() + mat.substring(1, 3),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : DFColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(selectedDailyLogs.length, (index) {
                    final val = selectedDailyLogs[index];
                    return Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Log ${index + 1}',
                            style: DFTextStyles.caption.copyWith(fontSize: 8, color: DFColors.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            val.toStringAsFixed(1),
                            style: DFTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: materialColors[selectedLogMaterial] ?? DFColors.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Technical summary
          RichText(
            text: TextSpan(
              style: DFTextStyles.caption.copyWith(fontSize: 11, color: DFColors.textSecondary, height: 1.45),
              children: [
                const TextSpan(
                  text: 'Trend Summary: ',
                  style: TextStyle(fontWeight: FontWeight.bold, color: DFColors.textPrimary),
                ),
                const TextSpan(
                  text: 'The graph tracks daily consumption fluctuations of all 5 core materials relative to their planned baseline (100% center line). Rather than examining materials in isolation, the engine analyzes how their concurrent changes correlate over time. At ',
                ),
                TextSpan(
                  text: '${(calculateDaysElapsedPct(project.startDate, project.expectedEndDate) * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: DFColors.textPrimary),
                ),
                const TextSpan(
                  text: ' timeline completion and an Equipment Idle Ratio of ',
                ),
                TextSpan(
                  text: '${(equipmentIdleRatio * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: DFColors.textPrimary),
                ),
                const TextSpan(
                  text: ', these combined fluctuations reveal whether resources are being wasted or if the site is operating at optimal scheduling efficiency.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.3),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Dynamic Chart Painter (renders actual data points) ──
class _DynamicChartPainter extends CustomPainter {
  final List<double> dataPoints;
  final double? estimatedValue;

  _DynamicChartPainter({required this.dataPoints, this.estimatedValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final maxVal = dataPoints.reduce((a, b) => a > b ? a : b) * 1.2;
    if (maxVal == 0) return;

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E3E6)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Estimated line (horizontal dashed)
    if (estimatedValue != null && estimatedValue! > 0) {
      final estY = size.height - (estimatedValue! / maxVal * size.height);
      final dashPaint = Paint()
        ..color = const Color(0xFF1A56A0).withValues(alpha: 0.3)
        ..strokeWidth = 1.5;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, estY), Offset(x + 4, estY), dashPaint);
      }
    }

    // Actual data line
    final linePaint = Paint()
      ..color = const Color(0xFF003E7E)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()..color = const Color(0xFF003E7E);
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x30003E7E), Color(0x00003E7E)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final spacing = dataPoints.length > 1 ? size.width / (dataPoints.length - 1) : size.width;

    for (int i = 0; i < dataPoints.length; i++) {
      final x = i * spacing;
      final y = size.height - (dataPoints[i] / maxVal * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // Draw dot
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    // Close fill path
    fillPath.lineTo((dataPoints.length - 1) * spacing, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DynamicChartPainter oldDelegate) {
    return oldDelegate.dataPoints != dataPoints || oldDelegate.estimatedValue != estimatedValue;
  }
}

// ── Multi-Material Trend Painter (renders 5 normalized material lines) ──
class _MultiMaterialTrendPainter extends CustomPainter {
  final Map<String, List<double>> multiMaterialData;
  final Map<String, double> materialMeans;
  final Map<String, Color> materialColors;

  _MultiMaterialTrendPainter({
    required this.multiMaterialData,
    required this.materialMeans,
    required this.materialColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (multiMaterialData.isEmpty) return;

    // 1. Draw horizontal grid lines (e.g., 4 lines)
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E3E6)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Draw Shared Dashed Baseline (exactly in the vertical center: y = size.height / 2)
    final centerY = size.height / 2;
    final dashPaint = Paint()
      ..color = const Color(0xFF5C6F84).withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, centerY), Offset(x + 4, centerY), dashPaint);
    }

    // 3. Compute relative values and maximum deviation symmetrically
    final Map<String, List<double>> relativeData = {};
    double maxDeviation = 0.2; // default minimum bound

    multiMaterialData.forEach((mat, points) {
      final mean = materialMeans[mat] ?? 0.0;
      final List<double> relPoints = [];
      for (var val in points) {
        if (mean == 0.0) {
          relPoints.add(1.0);
        } else {
          final rel = val / mean;
          relPoints.add(rel);
          final dev = (rel - 1.0).abs();
          if (dev > maxDeviation) {
            maxDeviation = dev;
          }
        }
      }
      relativeData[mat] = relPoints;
    });

    // Symmetric scaling bounds with a 15% edge padding safety margin
    final rangeVal = maxDeviation * 1.15;

    // 4. Paint 5 solid lines with soft circular dots
    relativeData.forEach((mat, relPoints) {
      if (relPoints.isEmpty) return;

      final color = materialColors[mat] ?? Colors.grey;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final dotPaint = Paint()..color = color;
      final path = Path();
      final spacing = relPoints.length > 1 ? size.width / (relPoints.length - 1) : size.width;

      for (int i = 0; i < relPoints.length; i++) {
        final x = i * spacing;
        final normalizedFraction = (relPoints[i] - (1.0 - rangeVal)) / (2 * rangeVal);
        final y = size.height - (normalizedFraction * size.height);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3, dotPaint);
      }
      canvas.drawPath(path, linePaint);
    });
  }

  @override
  bool shouldRepaint(covariant _MultiMaterialTrendPainter oldDelegate) {
    return oldDelegate.multiMaterialData != multiMaterialData ||
        oldDelegate.materialMeans != materialMeans ||
        oldDelegate.materialColors != materialColors;
  }
}

