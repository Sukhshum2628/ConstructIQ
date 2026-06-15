import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/milestone_model.dart';
import '../../providers/milestone_provider.dart';
import '../../services/milestone_service.dart';
import '../../utils/design_tokens.dart';

class ScheduleScreen extends ConsumerWidget {
  final String projectId;
  const ScheduleScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectMilestonesProvider(projectId));
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: const Text('Schedule & Milestones'),
        backgroundColor: DFColors.surface,
        foregroundColor: DFColors.textPrimary,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DFColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Milestone', style: TextStyle(color: Colors.white)),
        onPressed: () => _openAddEdit(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (milestones) {
          if (milestones.isEmpty) return _emptyState(context, ref);
          final ms = [...milestones]..sort((a, b) => a.plannedStart.compareTo(b.plannedStart));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryCard(ms),
              const SizedBox(height: 16),
              _curveCard(ms),
              const SizedBox(height: 16),
              Text('MILESTONES', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: DFColors.primary)),
              const SizedBox(height: 8),
              ...ms.map((m) => _milestoneTile(context, ref, m)),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timeline, size: 56, color: DFColors.outline),
              const SizedBox(height: 12),
              Text('No milestones yet', style: DFTextStyles.cardTitle),
              const SizedBox(height: 6),
              Text(
                'Add milestones (e.g. Foundation, Structure, Finishing) to track planned vs actual progress.',
                textAlign: TextAlign.center,
                style: DFTextStyles.caption,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openAddEdit(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Add first milestone'),
              ),
            ],
          ),
        ),
      );

  Widget _summaryCard(List<MilestoneModel> ms) {
    final now = DateTime.now();
    final planned = ScheduleMath.plannedAt(ms, now);
    final actual = ScheduleMath.actualOverall(ms);
    final delta = actual - planned;
    final (label, color) = delta >= 2
        ? ('Ahead of schedule', DFColors.success)
        : (delta <= -5 ? ('Behind schedule', DFColors.critical) : ('On track', DFColors.primary));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric('Planned', planned, DFColors.outline),
              _metric('Actual', actual, DFColors.primary),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (actual / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: DFColors.surfaceContainerHigh,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, double pct, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DFTextStyles.caption),
          Text('${pct.toStringAsFixed(0)}%', style: DFTextStyles.metricLarge.copyWith(color: color)),
        ],
      );

  Widget _curveCard(List<MilestoneModel> ms) {
    final start = ms.map((m) => m.plannedStart).reduce((a, b) => a.isBefore(b) ? a : b);
    final end = ms.map((m) => m.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b);
    final now = DateTime.now();
    final totalDays = end.difference(start).inDays.clamp(1, 100000);

    double xOf(DateTime d) => d.difference(start).inHours / 24.0;
    final nowX = xOf(now).clamp(0, totalDays.toDouble()).toDouble();

    const samples = 24;
    final planned = <FlSpot>[];
    final actual = <FlSpot>[];
    for (int i = 0; i <= samples; i++) {
      final x = totalDays * i / samples;
      final t = start.add(Duration(hours: (x * 24).round()));
      planned.add(FlSpot(x, ScheduleMath.plannedAt(ms, t)));
      if (!t.isAfter(now)) {
        actual.add(FlSpot(x, ScheduleMath.actualAt(ms, t, now)));
      }
    }
    // Ensure the actual line reaches "today".
    if (actual.isEmpty || actual.last.x < nowX) {
      actual.add(FlSpot(nowX, ScheduleMath.actualOverall(ms)));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                _legendDot(DFColors.outline, 'Planned'),
                const SizedBox(width: 16),
                _legendDot(DFColors.primary, 'Actual'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                minX: 0,
                maxX: totalDays.toDouble(),
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: DFColors.textCaption)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: totalDays / 4,
                      getTitlesWidget: (v, _) {
                        final d = start.add(Duration(days: v.round()));
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(DateFormat('MMM d').format(d), style: const TextStyle(fontSize: 9, color: DFColors.textCaption)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(verticalLines: [
                  VerticalLine(x: nowX, color: DFColors.accent, strokeWidth: 1.5, dashArray: [4, 4]),
                ]),
                lineBarsData: [
                  LineChartBarData(
                    spots: planned,
                    isCurved: true,
                    color: DFColors.outline,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 4],
                  ),
                  LineChartBarData(
                    spots: actual,
                    isCurved: true,
                    color: DFColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: DFColors.primary.withValues(alpha: 0.08)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: DFTextStyles.caption),
        ],
      );

  Widget _milestoneTile(BuildContext context, WidgetRef ref, MilestoneModel m) {
    final df = DateFormat('MMM d');
    final overdue = !m.isComplete && DateTime.now().isAfter(m.plannedEnd);
    final statusColor = m.isComplete ? DFColors.success : (overdue ? DFColors.critical : DFColors.primary);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(m.name, style: DFTextStyles.cardTitle)),
              if (overdue)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber_rounded, size: 16, color: DFColors.critical),
                ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'edit') _openAddEdit(context, ref, m);
                  if (v == 'delete') ref.read(milestoneServiceProvider).delete(projectId, m.id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                child: const Icon(Icons.more_vert, size: 18, color: DFColors.outline),
              ),
            ],
          ),
          Text('${df.format(m.plannedStart)} – ${df.format(m.plannedEnd)}  ·  weight ${m.weight.toStringAsFixed(m.weight == m.weight.roundToDouble() ? 0 : 1)}',
              style: DFTextStyles.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (m.progress / 100).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: DFColors.surfaceContainerHigh,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${m.progress.toStringAsFixed(0)}%', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [0, 25, 50, 75, 100].map((p) {
              final selected = m.progress.round() == p;
              return ChoiceChip(
                label: Text('$p%', style: const TextStyle(fontSize: 11)),
                selected: selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => ref.read(milestoneServiceProvider).setProgress(projectId, m.id, p.toDouble()),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _openAddEdit(BuildContext context, WidgetRef ref, MilestoneModel? existing) {
    showDialog(
      context: context,
      builder: (_) => _MilestoneDialog(
        projectId: projectId,
        existing: existing,
        onSave: (m) => ref.read(milestoneServiceProvider).save(m),
      ),
    );
  }
}

class _MilestoneDialog extends StatefulWidget {
  final String projectId;
  final MilestoneModel? existing;
  final void Function(MilestoneModel) onSave;
  const _MilestoneDialog({required this.projectId, this.existing, required this.onSave});

  @override
  State<_MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<_MilestoneDialog> {
  late final TextEditingController _name;
  late final TextEditingController _weight;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _weight = TextEditingController(text: (e?.weight ?? 1).toString());
    _start = e?.plannedStart ?? DateTime.now();
    _end = e?.plannedEnd ?? DateTime.now().add(const Duration(days: 14));
  }

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final init = isStart ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        if (isStart) {
          _start = d;
          if (_end.isBefore(_start)) _end = _start.add(const Duration(days: 7));
        } else {
          _end = d.isBefore(_start) ? _start : d;
        }
      });
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final weight = double.tryParse(_weight.text.trim()) ?? 1.0;
    final e = widget.existing;
    final m = (e ??
            MilestoneModel(
              id: const Uuid().v4(),
              projectId: widget.projectId,
              name: name,
              plannedStart: _start,
              plannedEnd: _end,
              createdAt: DateTime.now(),
            ))
        .copyWith(name: name, plannedStart: _start, plannedEnd: _end, weight: weight <= 0 ? 1.0 : weight);
    widget.onSave(m);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Milestone' : 'Edit Milestone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (e.g. Foundation)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Weight (relative effort)',
                helperText: 'Higher = bigger share of overall progress',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(true),
                  child: Text('Start: ${df.format(_start)}', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(false),
                  child: Text('End: ${df.format(_end)}', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
