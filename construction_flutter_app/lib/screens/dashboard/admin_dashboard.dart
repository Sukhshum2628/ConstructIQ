import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/project_provider.dart';
import '../../utils/design_tokens.dart';
import 'package:go_router/go_router.dart';
import '../../providers/deviation_provider.dart';
import '../../models/deviation_model.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(userProjectsProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text('ConstructIQ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
                  onPressed: () => context.push('/notifications'),
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final allDevsAsync = ref.watch(allDeviationsProvider);
                    final readIds = ref.watch(readNotificationsProvider);
                    
                    bool hasUnread = false;
                    if (allDevsAsync.hasValue) {
                      hasUnread = allDevsAsync.value!.any((d) => !readIds.contains(d.deviationId));
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
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreetingSection('Administrator'),
              const SizedBox(height: 24),
              _buildModernStatsHeader(projects, ref),
              const SizedBox(height: 32),
              const Text('Global Resource Footprint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildGlobalResourceChart(ref),
              const SizedBox(height: 32),
              const Text('Active Project Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...projects.map((p) => _buildProjectHealthCard(p, ref)),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildModernStatsHeader(List<dynamic> projects, WidgetRef ref) {
    final summaryAsync = ref.watch(deviationSummaryProvider);
    
    return summaryAsync.when(
      data: (summary) {
        final total = projects.length;
        final warnings = summary['warnings'] ?? 0;
        final criticals = summary['criticals'] ?? 0;
        final healthyCount = total - warnings - criticals;
        final efficiency = total > 0 ? (healthyCount / total * 100).toInt() : 100;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard('Projects', '$total', Icons.business, Colors.blue),
            _buildStatCard('Efficiency', '$efficiency%', Icons.speed, Colors.green),
            _buildStatCard('Overruns', '$criticals Sites', Icons.warning, Colors.orange),
          ],
        );
      },
      loading: () => const Center(child: LinearProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 105, // Fixed width for wrap consistency on small screens, or use LayoutBuilder if needed
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildGlobalResourceChart(WidgetRef ref) {
    final statsAsync = ref.watch(globalResourceStatsProvider);

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: statsAsync.when(
        data: (stats) {
          // Find max value for scaling
          double maxVal = stats.values.fold(1.0, (prev, element) => element > prev ? element : prev);
          
          return BarChart(
            BarChartData(
              barGroups: [
                _makeGroup(0, stats['cement'] ?? 0, Colors.blue),
                _makeGroup(1, stats['sand'] ?? 0, Colors.orange),
                _makeGroup(2, stats['bricks'] ?? 0, Colors.green),
                _makeGroup(3, stats['steel'] ?? 0, Colors.red),
                _makeGroup(4, stats['aggregate'] ?? 0, Colors.indigo),
              ],
              maxY: maxVal * 1.1,
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      const labels = ['Cem', 'Sand', 'Brick', 'Steel', 'Aggr'];
                      if (value.toInt() >= 0 && value.toInt() < labels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(labels[value.toInt()], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  BarChartGroupData _makeGroup(int x, double y, Color color) {
    return BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: color, width: 25, borderRadius: BorderRadius.circular(4))]);
  }

  Widget _buildProjectHealthCard(dynamic project, WidgetRef ref) {
    final devAsync = ref.watch(latestDeviationProvider(project.projectId));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => context.push('/projects/${project.projectId}'),
        leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.apartment, color: Colors.white)),
        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: devAsync.when(
          data: (dev) => Text('Status: ${project.status.name.toUpperCase()} • ML Risk: ${(dev.mlOverrunProbability * 100).toStringAsFixed(1)}%'),
          loading: () => const Text('Calculating health...'),
          error: (_, __) => const Text('Error loading deviation'),
        ),
        trailing: devAsync.when(
          data: (dev) {
            final severity = dev.overallSeverity;
            final isCritical = severity == 'critical';
            final isWarning = severity == 'warning' || severity == 'caution';
            
            final color = isCritical ? Colors.red : (isWarning ? Colors.orange : Colors.green);
            final label = severity.toUpperCase();

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            );
          },
          loading: () => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, __) => const Icon(Icons.error_outline, color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildGreetingSection(String name) {
    final String formattedDate = DateFormat('MMM d, yyyy').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Greetings $name', 
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
}
