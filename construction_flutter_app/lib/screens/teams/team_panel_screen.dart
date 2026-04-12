import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

class TeamPanelScreen extends ConsumerWidget {
  final String projectId;
  
  const TeamPanelScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfileDoc = ref.watch(userProfileProvider);
    final userProfile = userProfileDoc.value;
    final teamMembersAsync = ref.watch(teamMembersProvider(projectId));
    
    final bool canEdit = (userProfile?.role == UserRole.manager || userProfile?.role == UserRole.admin);
    final bool isOwner = userProfile?.role == UserRole.owner;

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        titleSpacing: 4.0, // Tightened gap from back arrow
        title: Text('Team Allocation', style: DFTextStyles.cardTitle.copyWith(fontSize: 18)),
        backgroundColor: DFColors.surface,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButton: canEdit ? FloatingActionButton.extended(
        backgroundColor: DFColors.primaryStitch,
        onPressed: () => _showAddMemberSheet(context, ref, projectId),
        icon: const Icon(Icons.person_add, color: DFColors.onPrimary),
        label: Text('Add Member', style: DFTextStyles.labelSm.copyWith(color: DFColors.onPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
      ) : null,
      body: CustomScrollView(
        slivers: [
          if (!canEdit)
            SliverToBoxAdapter(
              child: _buildBannerView(isOwner),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(DFSpacing.md),
            sliver: teamMembersAsync.when(
              loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              error: (err, _) => SliverFillRemaining(child: Center(child: Text('Error: $err'))),
              data: (members) {
                if (members.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Text('No team members allocated to this project yet.', style: DFTextStyles.body.copyWith(color: DFColors.textSecondary)),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _TeamMemberCard(member: members[index], projectId: projectId, canEdit: canEdit);
                    },
                    childCount: members.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerView(bool isOwner) {
    final bgColor = isOwner ? Colors.purple.shade50 : DFColors.surfaceContainerLow;
    final iconColor = isOwner ? Colors.purple : DFColors.outline;
    
    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOwner 
                  ? 'Owner view: Team allocations are read-only.'
                  : 'Engineer view: Contact your manager to modify team allocations.',
              style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context, WidgetRef ref, String projectId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DFColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _AddMemberSheet(projectId: projectId),
    );
  }
}

class _TeamMemberCard extends ConsumerWidget {
  final UserModel member;
  final String projectId;
  final bool canEdit;

  const _TeamMemberCard({required this.member, required this.projectId, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedProjectsAsync = ref.watch(userAssignedProjectsProvider(member.uid));
    
    return DFCard(
      margin: const EdgeInsets.only(bottom: DFSpacing.md),
      padding: const EdgeInsets.all(DFSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: DFColors.primaryLight,
                child: Text(member.name[0].toUpperCase(), style: DFTextStyles.cardTitle.copyWith(color: DFColors.primaryStitch)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: DFTextStyles.cardTitle),
                    Text(member.designation ?? 'Site Engineer', style: DFTextStyles.caption),
                  ],
                ),
              ),
              if (canEdit)
                GestureDetector(
                  onTap: () => _removeMember(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: DFColors.critical.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: DFColors.critical.withValues(alpha: 0.2)),
                    ),
                    child: Text('REMOVE', style: DFTextStyles.labelSm.copyWith(
                      color: DFColors.critical, 
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    )),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12), // Reduced spacing
          Text('ALSO ASSIGNED TO:', style: DFTextStyles.labelSm.copyWith(fontSize: 10, color: DFColors.textSecondary)),
          const SizedBox(height: 6), // Reduced spacing
          assignedProjectsAsync.when(
            loading: () => const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Text('Failed to load projects', style: DFTextStyles.caption),
            data: (projects) {
              final otherProjects = projects.where((p) => p.id != projectId).toList();
              if (otherProjects.isEmpty) {
                return Text('No other active allocations', style: DFTextStyles.caption.copyWith(fontStyle: FontStyle.italic, fontSize: 11));
              }
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: otherProjects.map((p) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DFColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(p.name, style: DFTextStyles.body.copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Are you sure you want to remove \${member.name} from this project?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('REMOVE', style: TextStyle(color: DFColors.critical)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('projects').doc(projectId).update({
          'teamMembers': FieldValue.arrayRemove([member.uid])
        });
        ref.invalidate(teamMembersProvider(projectId));
      } catch (e) {
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: \$e')));
        }
      }
    }
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  final String projectId;
  const _AddMemberSheet({required this.projectId});

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final availableEngineersAsync = ref.watch(availableEngineersProvider(widget.projectId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available Engineers', style: DFTextStyles.headline),
              const SizedBox(height: 16),
              Expanded(
                child: availableEngineersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: \$e')),
                  data: (engineers) {
                    if (engineers.isEmpty) {
                      return const Center(child: Text('No engineers found.'));
                    }
                    return ListView.builder(
                      controller: controller,
                      itemCount: engineers.length,
                      itemBuilder: (ctx, idx) {
                        final eng = engineers[idx];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: DFColors.primaryLight,
                            child: Text(eng.name[0].toUpperCase()),
                          ),
                          title: Text(eng.name, style: DFTextStyles.body),
                          subtitle: Text(eng.designation ?? 'Site Engineer', style: DFTextStyles.caption),
                          onTap: _isLoading ? null : () => _addEngineer(eng.uid),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle, color: DFColors.primaryStitch),
                            onPressed: _isLoading ? null : () => _addEngineer(eng.uid),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addEngineer(String uid) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).update({
        'teamMembers': FieldValue.arrayUnion([uid])
      });
      ref.invalidate(teamMembersProvider(widget.projectId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: \$e')));
         setState(() => _isLoading = false);
      }
    }
  }
}
