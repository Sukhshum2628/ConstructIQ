import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_button.dart';
import '../../models/delay_notice_model.dart';
import '../../services/delay_notice_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

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
  
  String _managerDecision = 'extend';
  bool _isActioning = false;

  @override
  void dispose() {
    _commentController.dispose();
    _managerNoteController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _castVote(VoteChoice vote) async {
    setState(() => _isActioning = true);
    try {
      final authState = ref.read(authStateChangesProvider);
      final uid = authState.value?.uid;
      final currentUser = await ref.read(userByIdProvider(uid!).future);
      
      await DelayNoticeService().castVote(
        projectId: widget.projectId,
        noticeId: widget.notice.id,
        engineerName: currentUser?.name ?? 'Engineer',
        vote: vote,
        comment: _commentController.text.trim(),
        notice: widget.notice,
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

  Future<void> _managerRespond() async {
    if (_managerNoteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a note for the engineers')),
      );
      return;
    }

    setState(() => _isActioning = true);
    try {
      final authState = ref.read(authStateChangesProvider);
      final uid = authState.value?.uid;
      
      int days = 0;
      if (_managerDecision == 'extend') {
        days = int.tryParse(_daysController.text) ?? 0;
        if (days <= 0) throw 'Please provide a valid number of days to extend';
      }

      await DelayNoticeService().managerRespond(
        projectId: widget.projectId,
        noticeId: widget.notice.id,
        decision: _managerDecision,
        daysExtended: days,
        managerNote: _managerNoteController.text.trim(),
        managerId: uid!,
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
          
          final isManager = user.role == 'manager' || user.role == 'admin';
          final needsVote = widget.notice.status == DelayNoticeStatus.pendingConsensus &&
              widget.notice.requiredVoters.contains(currentUid) &&
              !widget.notice.hasVoted(currentUid!);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(DFSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderPanel(),
                const SizedBox(height: DFSpacing.md),
                _buildDetailsPanel(),
                const SizedBox(height: DFSpacing.md),
                _buildVotesPanel(),
                
                if (widget.notice.managerResponse != null) ...[
                  const SizedBox(height: DFSpacing.md),
                  _buildManagerResponsePanel(),
                ],

                const SizedBox(height: DFSpacing.lg),
                
                if (needsVote) _buildVoteActionPanel(),
                if (isManager && widget.notice.status == DelayNoticeStatus.approved) 
                  _buildManagerActionPanel(),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildHeaderPanel() {
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
              Text(widget.notice.statusLabel.toUpperCase(), style: DFTextStyles.labelSm.copyWith(
                color: DFColors.primary, fontWeight: FontWeight.bold, letterSpacing: 1.1,
              )),
              Text(
                DateFormat('MMM dd, yyyy').format(widget.notice.reportedDate),
                style: DFTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.notice.title, style: DFTextStyles.headline.copyWith(fontSize: 20)),
          const SizedBox(height: 4),
          Text('Filed by ${widget.notice.createdByName}', style: DFTextStyles.body.copyWith(color: DFColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel() {
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
          _buildInfoRow('Delay Type', widget.notice.type.name.replaceAll('_', ' ').toUpperCase()),
          _buildInfoRow('Expected Arrival', DateFormat('MMM dd, yyyy').format(widget.notice.expectedDeliveryDate)),
          if (widget.notice.affectedMaterials.isNotEmpty)
            _buildInfoRow('Materials', widget.notice.affectedMaterials.join(', ').toUpperCase()),
          const Divider(height: 24),
          Text('DESCRIPTION', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.notice.description, style: DFTextStyles.body),
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

  Widget _buildVotesPanel() {
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
              Text('${widget.notice.votedCount}/${widget.notice.totalVoters} Voted', style: DFTextStyles.labelSm),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: widget.notice.votedCount / widget.notice.totalVoters,
            backgroundColor: DFColors.divider,
            valueColor: const AlwaysStoppedAnimation<Color>(DFColors.primary),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          ...widget.notice.votes.values.map((v) => Padding(
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

  Widget _buildManagerResponsePanel() {
    final resp = widget.notice.managerResponse!;
    final isExtended = resp.decision == 'extend';
    final color = resp.decision == 'reject' ? DFColors.critical : DFColors.success;

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
              : resp.decision == 'no_extension' 
                ? 'Delay acknowledged, but no deadline extension granted.'
                : 'Manager rejected this delay notice.',
            style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(resp.managerNote, style: DFTextStyles.body),
          const SizedBox(height: 12),
          Text(
            'Responded on ${DateFormat('MMM dd, yyyy').format(resp.respondedAt)}',
            style: DFTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildVoteActionPanel() {
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
                  onPressed: _isActioning ? null : () => _castVote(VoteChoice.agree),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DFButton(
                  label: 'Disagree',
                  icon: Icons.close_rounded,
                  outlined: true,
                  onPressed: _isActioning ? null : () => _castVote(VoteChoice.disagree),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManagerActionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.critical.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.critical.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MANAGER RESPONSE REQUIRED', style: DFTextStyles.labelSm.copyWith(
            fontWeight: FontWeight.bold, color: DFColors.critical,
          )),
          const SizedBox(height: 16),
          Column(
            children: [
              RadioListTile<String>(
                title: Text('Extend Deadline', style: DFTextStyles.body),
                value: 'extend',
                groupValue: _managerDecision,
                onChanged: (v) => setState(() => _managerDecision = v!),
              ),
              RadioListTile<String>(
                title: Text('No Extension (Just Acknowledge)', style: DFTextStyles.body),
                value: 'no_extension',
                groupValue: _managerDecision,
                onChanged: (v) => setState(() => _managerDecision = v!),
              ),
              RadioListTile<String>(
                title: Text('Reject Notice', style: DFTextStyles.body),
                value: 'reject',
                groupValue: _managerDecision,
                onChanged: (v) => setState(() => _managerDecision = v!),
              ),
            ],
          ),
          if (_managerDecision == 'extend') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Days to extend: '),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _daysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _managerNoteController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Note to engineers (required)...',
              filled: true,
              fillColor: DFColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: DFTextStyles.body,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: DFButton(
              label: 'Submit Response',
              onPressed: _isActioning ? null : _managerRespond,
              isLoading: _isActioning,
            ),
          ),
        ],
      ),
    );
  }
}
