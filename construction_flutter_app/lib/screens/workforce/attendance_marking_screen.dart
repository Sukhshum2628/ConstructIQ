import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/workforce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/workforce_model.dart';
import '../../models/attendance_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

class AttendanceMarkingScreen extends ConsumerStatefulWidget {
  final String projectId;
  const AttendanceMarkingScreen({super.key, required this.projectId});

  @override
  ConsumerState<AttendanceMarkingScreen> createState() => _AttendanceMarkingScreenState();
}

class _AttendanceMarkingScreenState extends ConsumerState<AttendanceMarkingScreen> {
  final Set<String> _presentWorkers = {};
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workforceByProjectProvider(widget.projectId));
    final attendanceAsync = ref.watch(dailyAttendanceProvider(widget.projectId));

    // Initialize state from existing attendance
    attendanceAsync.whenData((records) {
      for (var r in records) {
        if (r.status == AttendanceStatus.present) {
          _presentWorkers.add(r.workerId);
        }
      }
    });

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('Mark Attendance', style: DFTextStyles.cardTitle.copyWith(fontSize: 18)),
        backgroundColor: DFColors.surface,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveAttendance,
            child: _isLoading 
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('SAVE ALL', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: workersAsync.when(
        data: (workers) {
          if (workers.isEmpty) {
            return const Center(child: Text('No workers assigned to this project.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: workers.length,
            itemBuilder: (ctx, idx) {
              final worker = workers[idx];
              final isPresent = _presentWorkers.contains(worker.id);
              return _WorkerAttendanceTile(
                worker: worker,
                isPresent: isPresent,
                onToggle: (val) {
                  setState(() {
                    if (val) {
                      _presentWorkers.add(worker.id);
                    } else {
                      _presentWorkers.remove(worker.id);
                    }
                  });
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: \$e')),
      ),
    );
  }

  Future<void> _saveAttendance() async {
    setState(() => _isLoading = true);
    final user = ref.read(userProfileProvider).value;
    final workers = ref.read(workforceByProjectProvider(widget.projectId)).value ?? [];
    
    try {
      final service = ref.read(workforceServiceProvider);
      for (var worker in workers) {
        await service.markAttendance(
          workerId: worker.id,
          projectId: widget.projectId,
          status: _presentWorkers.contains(worker.id) ? AttendanceStatus.present : AttendanceStatus.absent,
          markedBy: user?.uid ?? 'system',
        );
      }
      ref.invalidate(dailyAttendanceProvider(widget.projectId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: \$e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _WorkerAttendanceTile extends StatelessWidget {
  final WorkerModel worker;
  final bool isPresent;
  final ValueChanged<bool> onToggle;

  const _WorkerAttendanceTile({required this.worker, required this.isPresent, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return DFCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isPresent ? DFColors.normalBg.withValues(alpha: 0.3) : DFColors.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(worker.name, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                Text(worker.trade.name.toUpperCase(), style: DFTextStyles.caption.copyWith(fontSize: 10, letterSpacing: 0.5)),
              ],
            ),
          ),
          Switch.adaptive(
            value: isPresent,
            onChanged: onToggle,
            activeThumbColor: DFColors.normal,
            activeTrackColor: DFColors.normal.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
