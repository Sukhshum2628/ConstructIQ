import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/resource_log_provider.dart';
import '../../models/resource_log_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_pill.dart';
import '../../widgets/empty_state_widget.dart';

class LogHistoryScreen extends ConsumerWidget {
  final String? projectId;
  const LogHistoryScreen({super.key, this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (projectId == null) {
      return Scaffold(
        backgroundColor: DFColors.background,
        appBar: AppBar(backgroundColor: DFColors.background, elevation: 0),
        body: const Center(child: Text('NO PROJECT TRACE DETECTED')),
      );
    }
    
    final logsAsync = ref.watch(projectLogsProvider(projectId!));

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        centerTitle: false,
        title: Text('FIELD LOG ARCHIVE', 
          style: DFTextStyles.caption.copyWith(
            color: DFColors.primary, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 2.0
          )
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DFColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(DFSpacing.lg),
              child: EmptyStateWidget(
                message: 'CHRONOLOGY EMPTY: NO LOGS DETECTED',
                icon: Icons.history_rounded,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(DFSpacing.lg),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _LogHistoryItem(log: log);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primary)),
        error: (e, s) => Center(child: Text('ERR: $e', style: DFTextStyles.caption.copyWith(color: DFColors.critical))),
      ),
    );
  }
}

class _LogHistoryItem extends StatelessWidget {
  final ResourceLogModel log;
  const _LogHistoryItem({required this.log});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DFCard(
        padding: const EdgeInsets.all(20),
        hasShadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd MMM yyyy • HH:mm').format(log.createdAt).toUpperCase(), 
                  style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.textSecondary)),
                const DFPill(label: 'SYNCED', severity: 'normal'),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: DFColors.divider),
            const SizedBox(height: 16),
            _buildResourceRow('BRICKS', '${log.materialUsage['bricks'] ?? 0} UNITS', Icons.grid_view_rounded),
            _buildResourceRow('CEMENT', '${log.materialUsage['cement'] ?? 0} BAGS', Icons.inventory_2_outlined),
            _buildResourceRow('SAND', '${log.materialUsage['sand'] ?? 0} M³', Icons.layers_outlined),
            _buildResourceRow('LABOR', '${log.laborHours} HRS', Icons.engineering_outlined),
            const SizedBox(height: 12),
            Text('LOGGED BY: ${log.loggedBy.toString().substring(0, log.loggedBy.length > 8 ? 8 : log.loggedBy.length).toUpperCase()}', 
              style: DFTextStyles.caption.copyWith(fontSize: 8, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: DFColors.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(label, style: DFTextStyles.caption.copyWith(fontSize: 10)),
          const Spacer(),
          Text(value, style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
        ],
      ),
    );
  }
}
