import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import 'project_search_delegate.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_pill.dart';
import '../../widgets/empty_state_widget.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../models/project_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/estimation_provider.dart';

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      body: SafeArea(
        child: projectsAsync.when(
          data: (projects) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(DFSpacing.lg, DFSpacing.lg, DFSpacing.lg, DFSpacing.md),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('All Projects', style: DFTextStyles.screenTitle),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.search, color: DFColors.primary, size: 28),
                                  onPressed: () => showSearch(
                                    context: context,
                                    delegate: ProjectSearchDelegate(projects),
                                  ),
                                ),
                                if (ref.watch(currentUserProfileProvider)?.role == UserRole.manager ||
                                    ref.watch(currentUserProfileProvider)?.role == UserRole.admin)
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: DFColors.primary, size: 32),
                                    onPressed: () => context.push('/create-project'),
                                  ),
                                if (ref.watch(currentUserProfileProvider)?.role == UserRole.owner)
                                  IconButton(
                                    icon: const Icon(Icons.add_link, color: Colors.orange, size: 32),
                                    onPressed: () => _showLinkProjectDialog(context, ref),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: DFSpacing.xs),
                        Text('${projects.length} active projects', style: DFTextStyles.cardSubtitle),
                      ],
                    ),
                  ),
                ),
                if (projects.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: EmptyStateWidget(
                        message: 'No projects detected',
                        icon: Icons.architecture,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final p = projects[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: DFSpacing.md),
                            child: _ProjectListItem(project: p),
                          );
                        },
                        childCount: projects.length,
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primary)),
          error: (e, s) => Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  'STATION ERROR: $e', 
                  textAlign: TextAlign.center,
                  style: DFTextStyles.body.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold)
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLinkProjectDialog(BuildContext context, WidgetRef ref) async {
    final TextEditingController codeController = TextEditingController();
    bool isLoading = false;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.vpn_key_rounded, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Text('Link New Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the Owner Invitation Code provided by your Project Manager to link their project to your portfolio.',
                    style: TextStyle(fontSize: 13, color: DFColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Owner Invitation Code',
                      hintText: 'e.g. CQ-OWN-XXXX',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.add_link),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('CANCEL', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DFColors.primaryStitch,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter an invitation code')),
                            );
                            return;
                          }

                          setState(() => isLoading = true);
                          try {
                            // 1. Fetch current user ID
                            final uid = ref.read(currentUserProfileProvider)?.uid;
                            if (uid == null) throw Exception('User not authenticated.');

                            // 2. Query project matching ownerCode
                            final querySnap = await FirebaseFirestore.instance
                                .collection('projects')
                                .where('ownerCode', isEqualTo: code)
                                .limit(1)
                                .get();

                            if (querySnap.docs.isEmpty) {
                              throw Exception('Invalid Invitation Code. No matching project found.');
                            }

                            final projectDoc = querySnap.docs.first;
                            final projectData = projectDoc.data();

                            if (projectData['ownerUserId'] != null) {
                              throw Exception('This project already has an assigned owner.');
                            }

                            final projectId = projectDoc.id;

                            // 3. Update Project with Owner UID
                            await FirebaseFirestore.instance
                                .collection('projects')
                                .doc(projectId)
                                .update({'ownerUserId': uid});

                            // 4. Update User Profile with Project ID in assignedProjects
                            final userDoc = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .get();

                            final userData = userDoc.data() ?? {};
                            final List<String> currentProjects =
                                List<String>.from(userData['assignedProjects'] ?? []);

                            if (!currentProjects.contains(projectId)) {
                              currentProjects.add(projectId);
                            }

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .update({'assignedProjects': currentProjects});

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Linked successfully to project "${projectData['name']}"!'),
                                  backgroundColor: DFColors.normal,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error linking project: ${e.toString().replaceAll('Exception: ', '')}'),
                                  backgroundColor: DFColors.critical,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('LINK PROJECT'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ProjectListItem extends ConsumerWidget {
  final dynamic project;
  const _ProjectListItem({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userRole = ref.watch(currentUserProfileProvider)?.role;
    final isManager = userRole == UserRole.manager || userRole == UserRole.admin;

    // Determine severity color for the left strip
    Color severityColor;
    String status = (project.status as ProjectStatus).name.toLowerCase();
    
    if (status == 'closed' || status == 'completed') {
      severityColor = DFColors.normal;
    } else if (status == 'critical' || status == 'delayed') {
      severityColor = DFColors.critical;
    } else if (status == 'warning' || status == 'risk' || status == 'onhold') {
      severityColor = DFColors.warning;
    } else {
      severityColor = DFColors.primary;
    }

    return DFCard(
      padding: EdgeInsets.zero,
      hasShadow: true,
      onTap: () => context.push('/projects/${project.projectId}'),
      onLongPress: isManager ? () => _showDeleteConfirmation(context, ref) : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Severity Strip
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: severityColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DFSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            project.name,
                            style: DFTextStyles.cardTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DFPill(
                          label: status.toUpperCase(),
                          severity: (status == 'critical') ? 'critical' : (status == 'warning' || status == 'onhold' ? 'warning' : 'normal'),
                        ),
                      ],
                    ),
                    const SizedBox(height: DFSpacing.xs),
                    Text(project.location, style: DFTextStyles.cardSubtitle),
                    const SizedBox(height: 4),
                    Consumer(
                      builder: (context, ref, child) {
                        final creatorAsync = ref.watch(userByIdProvider(project.createdBy));
                        return creatorAsync.when(
                          data: (user) => Text('Managed by: ${user?.name ?? 'Unknown'}', 
                            style: DFTextStyles.caption.copyWith(
                              fontSize: 10, 
                              color: DFColors.primaryStitch.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            )),
                          loading: () => const SizedBox(height: 12),
                          error: (_, __) => const SizedBox(height: 12),
                        );
                      },
                    ),
                    const SizedBox(height: DFSpacing.md),
                    Row(
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final estimateAsync = ref.watch(latestEstimateProvider(project.projectId));
                            final rawMaterialCost = ref.watch(estimatedCostProvider(project.projectId));

                            return estimateAsync.when(
                              data: (estimate) {
                                final displayMaterialCost = estimate?.manualMaterialCost ?? rawMaterialCost;
                                final displayContractorEstimate = estimate?.manualContractorEstimate ?? (displayMaterialCost * 1.5);
                                final totalBudget = displayMaterialCost + displayContractorEstimate;
                                
                                final String formattedBudget;
                                if (totalBudget % 1 == 0) {
                                  formattedBudget = '₹${totalBudget.toInt()}';
                                } else {
                                  formattedBudget = '₹${totalBudget.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '')}';
                                }

                                return _StatItem(label: 'BUDGET', value: formattedBudget);
                              },
                              loading: () => _StatItem(label: 'BUDGET', value: '₹${project.plannedBudget.toStringAsFixed(0)}'),
                              error: (_, __) => _StatItem(label: 'BUDGET', value: '₹${project.plannedBudget.toStringAsFixed(0)}'),
                            );
                          },
                        ),
                        const SizedBox(width: DFSpacing.lg),
                        _StatItem(label: 'TIMELINE', value: DateFormat('MMM yyyy').format(project.startDate.add(Duration(days: project.durationDays > 0 ? project.durationDays : 90)))),
                        const Spacer(),
                        const Icon(Icons.chevron_right, color: DFColors.textCaption, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, WidgetRef ref) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: DFColors.critical),
              SizedBox(width: 12),
              Text('Delete Project'),
            ],
          ),
          content: Text('Delete "${project.name}" and all associated data? This cannot be undone.', 
            style: DFTextStyles.body.copyWith(fontSize: 14)),
          actions: <Widget>[
            TextButton(
              child: Text('CANCEL', style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DFColors.critical, foregroundColor: Colors.white),
              child: const Text('DELETE'),
              onPressed: () async {
                try {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Deleting project...'), behavior: SnackBarBehavior.floating),
                  );
                  
                  await ref.read(projectServiceProvider).deleteProject(project.projectId);
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Project deleted successfully'), backgroundColor: DFColors.normal, behavior: SnackBarBehavior.floating),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: DFColors.critical, behavior: SnackBarBehavior.floating),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
