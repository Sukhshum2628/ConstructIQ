import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/design_tokens.dart';
import '../../models/project_model.dart';

import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../models/deviation_model.dart';


class ManagerAnalytics extends ConsumerStatefulWidget {
  const ManagerAnalytics({super.key});

  @override
  ConsumerState<ManagerAnalytics> createState() => _ManagerAnalyticsState();
}

class _ManagerAnalyticsState extends ConsumerState<ManagerAnalytics> {
  String? _selectedProjectId;
  String _selectedMaterial = 'cement';
  final List<String> _materialKeys = ['cement', 'bricks', 'steel', 'sand'];

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        centerTitle: false,
        leading: Container(
          margin: const EdgeInsets.only(left: 12),
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: DFColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
        title: Text('Project Analytics', style: DFTextStyles.screenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: DFColors.primary),
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
    final deviationAsync = ref.watch(latestDeviationProvider(_selectedProjectId!));


    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg, vertical: DFSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Context Header with Selector
          _buildProjectContextHeader(context, projects, selectedProject),
          const SizedBox(height: DFSpacing.xxl),

          // 1. Material Usage Trend (from resource logs)
          _buildMaterialUsageTrend(),
          const SizedBox(height: DFSpacing.lg),

          // 2. Deviation Severity (from deviation data)
          deviationAsync.when(
            data: (devData) => _buildDeviationSeverity(devData),
            loading: () => _buildShimmerCard(200),
            error: (_, __) => _buildDeviationSeverity(null),
          ),
          const SizedBox(height: DFSpacing.lg),

          // 3. Equipment Utilisation (from resource logs)
          _buildEquipmentUtilisation(),
          const SizedBox(height: DFSpacing.lg),

          // 4. Report Generation Card
          _buildReportGenerationCard(context),
          const SizedBox(height: DFSpacing.xxl),
        ],
      ),
    );
  }

  // ── Project Context Header with Dropdown ──
  Widget _buildProjectContextHeader(BuildContext context, List<ProjectModel> projects, ProjectModel selected) {
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
              icon: const Icon(Icons.keyboard_arrow_down, color: DFColors.primary),
              style: DFTextStyles.screenTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: DFColors.primary),
              items: projects.map((p) => DropdownMenuItem(value: p.projectId, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedProjectId = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(selected.location, style: DFTextStyles.body.copyWith(fontSize: 13, color: DFColors.textSecondary)),
        const SizedBox(height: DFSpacing.md),
        Wrap(
          spacing: 8,
          children: [
            _buildHeaderButton('View Insights', Icons.insights, true, () {}),
          ],
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
        // Extract data for the selected material (last 7 logs)
        final displayLogs = logs.length > 7 ? logs.sublist(logs.length - 7) : logs;
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
    );
  }

  String _formatLogDate(Map<String, dynamic> log) {
    final ts = log['createdAt'] as Timestamp? ?? log['logDate'] as Timestamp?;
    if (ts == null) return '';
    final d = ts.toDate();
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
      loading: () => _buildShimmerCard(200),
      error: (e, _) => Center(child: Text('Error: $e')),
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
