import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_button.dart';
import '../../models/delay_notice_model.dart';
import '../../models/user_model.dart';
import '../../services/delay_notice_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/delay_notice_provider.dart';

class DelayNoticeDetailScreen extends ConsumerStatefulWidget {
  final DelayNotice notice;
  final String projectId;

  const DelayNoticeDetailScreen({
    super.key, 
    required this.notice,
    required this.projectId,
  });

  @override
  ConsumerState<DelayNoticeDetailScreen> createState() => _DelayNoticeDetailScreenState();
}

class _DelayNoticeDetailScreenState extends ConsumerState<DelayNoticeDetailScreen> {
  final _commentController = TextEditingController();
  final _managerNoteController = TextEditingController();
  final _daysController = TextEditingController(text: '1');
  bool _isActioning = false;

  @override
  void dispose() {
    _commentController.dispose();
    _managerNoteController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _castVote(VoteChoice vote, DelayNotice notice) async {
    setState(() => _isActioning = true);
    try {
      final authState = ref.read(authStateChangesProvider);
      final uid = authState.value?.uid;
      if (uid == null) throw 'User not authenticated';
      final currentUser = await ref.read(userByIdProvider(uid).future);
      
      await DelayNoticeService().castVote(
        projectId: widget.projectId,
        noticeId: notice.id,
        engineerName: currentUser?.name ?? 'Engineer',
        vote: vote,
        comment: _commentController.text.trim(),
        notice: notice,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vote cast successfully'), backgroundColor: DFColors.success),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: DFColors.critical),
      );
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _managerRespond(String decision, DelayNotice notice) async {
    if (_managerNoteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide manager notes')),
      );
      return;
    }

    setState(() => _isActioning = true);
    try {
      final authState = ref.read(authStateChangesProvider);
      final uid = authState.value?.uid;
      if (uid == null) throw 'Manager not authenticated';
      
      int days = 0;
      if (decision == 'approved') {
        days = int.tryParse(_daysController.text) ?? 0;
        if (days <= 0) throw 'Please provide a valid number of days to extend';
      }

      await DelayNoticeService().managerRespond(
        projectId: widget.projectId,
        noticeId: notice.id,
        decision: decision,
        daysExtended: days,
        notes: _managerNoteController.text.trim(),
        managerId: uid,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Response submitted successfully'), backgroundColor: DFColors.success),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: DFColors.critical),
      );
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateChangesProvider);
    final currentUid = authState.value?.uid;
    final userAsync = ref.watch(userByIdProvider(currentUid ?? ''));

    final noticesAsync = ref.watch(delayNoticesProvider(widget.projectId));
    final notice = noticesAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (n) => n.id == widget.notice.id,
        orElse: () => widget.notice,
      ),
      orElse: () => widget.notice,
    );

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('Notice Details', style: DFTextStyles.sectionHeader.copyWith(color: Colors.white)),
        backgroundColor: DFColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text('User not found'));
          
          final isManager = user.role == UserRole.manager || user.role == UserRole.admin;
          final isActionable = notice.status == DelayNoticeStatus.pendingConsensus || 
                             notice.status == DelayNoticeStatus.approved;
          
          final needsVote = notice.status == DelayNoticeStatus.pendingConsensus &&
              currentUid != null &&
              notice.requiredVoters.contains(currentUid) &&
              !notice.hasVoted(currentUid);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(DFSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderPanel(notice),
                const SizedBox(height: DFSpacing.md),
                _buildDetailsPanel(notice),
                const SizedBox(height: DFSpacing.md),
                _buildVotesPanel(notice),
                
                if (notice.managerResponse != null) ...[
                  const SizedBox(height: DFSpacing.md),
                  _buildManagerResponsePanel(notice),
                ],

                const SizedBox(height: DFSpacing.lg),
                
                if (needsVote) _buildVoteActionPanel(notice),
                if (isManager && isActionable && notice.managerResponse == null) 
                  _buildManagerActionPanel(notice),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildHeaderPanel(DelayNotice notice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(notice.statusLabel.toUpperCase(), style: DFTextStyles.labelSm.copyWith(
                color: DFColors.primary, fontWeight: FontWeight.bold, letterSpacing: 1.1,
              )),
              Text(
                DateFormat('MMM dd, yyyy').format(notice.reportedDate),
                style: DFTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(notice.title, style: DFTextStyles.headline.copyWith(fontSize: 20)),
          const SizedBox(height: 4),
          Text('Filed by ${notice.createdByName}', style: DFTextStyles.body.copyWith(color: DFColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(DelayNotice notice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Delay Type', notice.type.name.replaceAll('_', ' ').toUpperCase()),
          _buildInfoRow('Expected Arrival', DateFormat('MMM dd, yyyy').format(notice.expectedDeliveryDate)),
          if (notice.affectedMaterials.isNotEmpty)
            _buildInfoRow('Materials', notice.affectedMaterials.join(', ').toUpperCase()),
          const Divider(height: 24),
          Text('DESCRIPTION', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(notice.description, style: DFTextStyles.body),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: DFTextStyles.caption),
          Text(value, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildVotesPanel(DelayNotice notice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TEAM CONSENSUS', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
              Text('${notice.votedCount}/${notice.totalVoters} Voted', style: DFTextStyles.labelSm),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: notice.totalVoters > 0 ? notice.votedCount / notice.totalVoters : 0.0,
            backgroundColor: DFColors.divider,
            valueColor: const AlwaysStoppedAnimation<Color>(DFColors.primary),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          ...notice.votes.values.map((v) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  v.vote == VoteChoice.agree ? Icons.check_circle : Icons.cancel,
                  color: v.vote == VoteChoice.agree ? DFColors.success : DFColors.critical,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${v.engineerName} • ${v.vote == VoteChoice.agree ? 'Agreed' : 'Disagreed'}',
                        style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (v.comment.isNotEmpty)
                        Text(v.comment, style: DFTextStyles.caption.copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildManagerResponsePanel(DelayNotice notice) {
    final resp = notice.managerResponse!;
    final isExtended = resp.decision == 'approved';
    final color = resp.decision == 'rejected' ? DFColors.critical : DFColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MANAGER RESPONSE', style: DFTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.bold, color: color,
          )),
          const SizedBox(height: 8),
          Text(
            isExtended 
              ? 'Deadline extended by ${resp.daysExtended} days.' 
              : 'Manager rejected this delay notice.',
            style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(resp.notes, style: DFTextStyles.body),
          const SizedBox(height: 12),
          Text(
            'Responded on ${DateFormat('MMM dd, yyyy').format(resp.respondedAt)}',
            style: DFTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildVoteActionPanel(DelayNotice notice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DO YOU AGREE THIS DELAY IS REAL?', style: DFTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.bold, color: DFColors.warning,
          )),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            decoration: InputDecoration(
              hintText: 'Optional comment for the team...',
              filled: true,
              fillColor: DFColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: DFTextStyles.body,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DFButton(
                  label: 'Agree',
                  icon: Icons.check_rounded,
                  onPressed: _isActioning ? null : () => _castVote(VoteChoice.agree, notice),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DFButton(
                  label: 'Disagree',
                  icon: Icons.close_rounded,
                  outlined: true,
                  onPressed: _isActioning ? null : () => _castVote(VoteChoice.disagree, notice),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManagerActionPanel(DelayNotice notice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MANAGER APPROVAL REQUIRED', style: DFTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.bold, color: DFColors.primary,
          )),
          const SizedBox(height: 20),
          
          Text('Days to Extend', style: DFTextStyles.caption),
          const SizedBox(height: 8),
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'e.g. 7',
              filled: true,
              fillColor: DFColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
            ),
            style: DFTextStyles.body,
          ),
          
          const SizedBox(height: 16),
          Text('Manager Notes', style: DFTextStyles.caption),
          const SizedBox(height: 8),
          TextField(
            controller: _managerNoteController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter approval/rejection rationale...',
              filled: true,
              fillColor: DFColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: DFTextStyles.body,
          ),
          
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: DFButton(
                  label: 'Approve & Extend',
                  icon: Icons.check_circle_outline,
                  onPressed: _isActioning ? null : () => _managerRespond('approved', notice),
                  isLoading: _isActioning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DFButton(
                  label: 'Reject',
                  icon: Icons.block,
                  outlined: true,
                  onPressed: _isActioning ? null : () => _managerRespond('rejected', notice),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
