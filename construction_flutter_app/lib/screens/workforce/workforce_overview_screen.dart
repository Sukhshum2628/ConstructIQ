import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/workforce_provider.dart';
import '../../models/workforce_model.dart';
import '../../models/attendance_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

class WorkforceOverviewScreen extends ConsumerWidget {
  final String projectId;
  const WorkforceOverviewScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workforceByProjectProvider(projectId));
    final attendanceAsync = ref.watch(dailyAttendanceProvider(projectId));

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('Workforce Overview', style: DFTextStyles.cardTitle.copyWith(fontSize: 18)),
        backgroundColor: DFColors.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headcount Stats
            attendanceAsync.when(
              data: (attendance) => _buildStatCards(attendance, workersAsync.value ?? []),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: \$e'),
            ),
            const SizedBox(height: 32),
            _buildTradeDistribution(workersAsync.value ?? []),
            const SizedBox(height: 32),
            Text('STAFF LIST', style: DFTextStyles.labelSm),
            const SizedBox(height: 16),
            workersAsync.when(
              data: (workers) => _buildWorkerList(workers, attendanceAsync.value ?? []),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: \$e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards(List<AttendanceRecord> attendance, List<WorkerModel> allWorkers) {
    final presentCount = attendance.where((a) => a.status == AttendanceStatus.present).length;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'PRESENT TODAY',
            value: '$presentCount',
            subLabel: 'Out of ${allWorkers.length}',
            icon: Icons.people_alt_rounded,
            color: DFColors.primaryStitch,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'AVAILABILITY',
            value: '${allWorkers.isEmpty ? 0 : (presentCount / allWorkers.length * 100).toInt()}%',
            subLabel: 'Current utilization',
            icon: Icons.show_chart_rounded,
            color: DFColors.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildTradeDistribution(List<WorkerModel> workers) {
    final trades = <WorkerTrade, int>{};
    for (var w in workers) {
      trades[w.trade] = (trades[w.trade] ?? 0) + 1;
    }

    return DFCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRADE BREAKDOWN', style: DFTextStyles.labelSm),
          const SizedBox(height: 16),
          ...trades.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(e.key.name.toUpperCase(), style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: workers.isEmpty ? 0 : e.value / workers.length,
                      backgroundColor: DFColors.surfaceContainerLow,
                      color: DFColors.primaryStitch,
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${e.value}', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildWorkerList(List<WorkerModel> workers, List<AttendanceRecord> attendance) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: workers.length,
      itemBuilder: (context, index) {
        final worker = workers[index];
        final record = attendance.any((a) => a.workerId == worker.id && a.status == AttendanceStatus.present);
        
        return DFCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: DFColors.surfaceContainerLow,
                child: Icon(Icons.person_outline_rounded, color: DFColors.primaryStitch, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.name, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                    Text(worker.trade.name.toUpperCase(), style: DFTextStyles.caption.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: record ? DFColors.normalBg : DFColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  record ? 'PRESENT' : 'NOT MARKED',
                  style: DFTextStyles.labelSm.copyWith(
                    fontSize: 9, 
                    fontWeight: FontWeight.bold,
                    color: record ? DFColors.normal : DFColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String subLabel;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.subLabel, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return DFCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(value, style: DFTextStyles.metricLarge.copyWith(height: 1.0)),
          const SizedBox(height: 4),
          Text(label, style: DFTextStyles.labelSm.copyWith(fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subLabel, style: DFTextStyles.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
