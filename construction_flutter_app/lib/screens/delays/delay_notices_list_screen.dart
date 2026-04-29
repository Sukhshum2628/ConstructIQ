import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../utils/design_tokens.dart';
import '../../models/delay_notice_model.dart';
import '../../providers/delay_notice_provider.dart';
import '../../providers/auth_provider.dart';
import 'delay_notice_detail_screen.dart';

class DelayNoticesListScreen extends ConsumerWidget {
  final String projectId;

  const DelayNoticesListScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticesAsync = ref.watch(delayNoticesProvider(projectId));
    final authState = ref.watch(authStateChangesProvider);
    final currentUid = authState.value?.uid;

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('Delay Notices', style: DFTextStyles.sectionHeader.copyWith(color: Colors.white)),
        backgroundColor: DFColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: noticesAsync.when(
        data: (notices) {
          if (notices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_edu_outlined, size: 64, color: DFColors.textCaption.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No delay notices filed yet', style: DFTextStyles.cardSubtitle),
                ],
              ),
            );
          }

          // Group by status: approved first for managers? No, spec says "approved prominently at the top"
          // Let's just filter for the UI
          final approved = notices.where((n) => n.status == DelayNoticeStatus.approved).toList();
          final others = notices.where((n) => n.status != DelayNoticeStatus.approved).toList();

          return ListView(
            padding: const EdgeInsets.all(DFSpacing.md),
            children: [
              if (approved.isNotEmpty) ...[
                Text('AWAITING REVIEW', style: DFTextStyles.labelSm.copyWith(
                  fontWeight: FontWeight.bold, color: DFColors.critical, letterSpacing: 1.2,
                )),
                const SizedBox(height: DFSpacing.sm),
                ...approved.map((n) => _NoticeCard(notice: n, currentUid: currentUid, projectId: projectId)),
                const SizedBox(height: DFSpacing.md),
              ],
              if (others.isNotEmpty) ...[
                if (approved.isNotEmpty)
                  Text('RECENT NOTICES', style: DFTextStyles.labelSm.copyWith(
                    fontWeight: FontWeight.bold, color: DFColors.textSecondary, letterSpacing: 1.2,
                  )),
                const SizedBox(height: DFSpacing.sm),
                ...others.map((n) => _NoticeCard(notice: n, currentUid: currentUid, projectId: projectId)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final DelayNotice notice;
  final String? currentUid;
  final String projectId;

  const _NoticeCard({required this.notice, this.currentUid, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final needsVote = notice.status == DelayNoticeStatus.pendingConsensus &&
        notice.requiredVoters.contains(currentUid) &&
        !notice.hasVoted(currentUid!);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: needsVote ? DFColors.warning : DFColors.divider),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DelayNoticeDetailScreen(notice: notice, projectId: projectId)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TypeIcon(type: notice.type),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notice.title, style: DFTextStyles.cardTitle),
                        const SizedBox(height: 4),
                        Text(
                          'Filed by ${notice.createdByName} • ${DateFormat('MMM dd').format(notice.reportedDate)}',
                          style: DFTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: notice.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${notice.votedCount}/${notice.totalVoters} voted • ${notice.agreeCount} agree',
                    style: DFTextStyles.labelSm,
                  ),
                  if (needsVote)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: DFColors.warningBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('VOTE REQUIRED', style: DFTextStyles.labelSm.copyWith(
                        color: DFColors.warning, fontWeight: FontWeight.bold,
                      )),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final DelayNoticeType type;
  const _TypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon = switch (type) {
      DelayNoticeType.materialDelivery => Icons.local_shipping_outlined,
      DelayNoticeType.equipment        => Icons.construction_outlined,
      DelayNoticeType.labour           => Icons.groups_outlined,
      DelayNoticeType.other            => Icons.info_outline,
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DFColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: DFColors.primary, size: 20),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final DelayNoticeStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = switch (status) {
      DelayNoticeStatus.pendingConsensus        => DFColors.warning,
      DelayNoticeStatus.approved                => DFColors.critical,
      DelayNoticeStatus.rejectedByTeam          => DFColors.textCaption,
      DelayNoticeStatus.acknowledgedExtended    => DFColors.success,
      DelayNoticeStatus.acknowledgedNoExtension => Colors.blue,
      DelayNoticeStatus.rejectedByManager       => DFColors.textCaption,
    };

    String label = switch (status) {
      DelayNoticeStatus.pendingConsensus        => 'PENDING',
      DelayNoticeStatus.approved                => 'APPROVED',
      DelayNoticeStatus.rejectedByTeam          => 'TEAM REJECT',
      DelayNoticeStatus.acknowledgedExtended    => 'EXTENDED',
      DelayNoticeStatus.acknowledgedNoExtension => 'ACKNOWLEDGED',
      DelayNoticeStatus.rejectedByManager       => 'REJECTED',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: DFTextStyles.labelSm.copyWith(
        color: color, fontWeight: FontWeight.bold, fontSize: 10,
      )),
    );
  }
}
