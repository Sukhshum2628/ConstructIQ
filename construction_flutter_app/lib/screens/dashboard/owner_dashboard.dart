import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/project_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workforce_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../models/project_model.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

class OwnerDashboard extends ConsumerWidget {
  const OwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProfileProvider).value;
    final projectsAsync = ref.watch(userProjectsProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.surface,
        elevation: 0,
        titleSpacing: 24,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Owner Dashboard', style: DFTextStyles.cardTitle.copyWith(fontSize: 18)),
            Text(user?.name ?? 'Project Owner', style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: DFColors.critical),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return _buildNoProjectState(context, ref);
          }
          final project = projects.first;
          return _buildOwnerDashboardContent(context, ref, project);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildNoProjectState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 64, color: DFColors.outlineVariant),
            const SizedBox(height: 16),
            Text('Awaiting Project Linking', style: DFTextStyles.screenTitle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(
              'Your digital portfolio is currently empty. Once our administrators link your project to this account, you will see real-time financials and site progress here.',
              textAlign: TextAlign.center,
              style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => ref.read(authServiceProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Switch Account'),
              style: OutlinedButton.styleFrom(foregroundColor: DFColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerDashboardContent(BuildContext context, WidgetRef ref, ProjectModel project) {
    final workforceAsync = ref.watch(dailyAttendanceProvider(project.id));
    final deviationAsync = ref.watch(latestDeviationProvider(project.id));
    final currencyFormat = NumberFormat.compactCurrency(symbol: '₹', locale: 'en_IN');

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userProjectsProvider);
        ref.invalidate(dailyAttendanceProvider(project.id));
        ref.invalidate(latestDeviationProvider(project.id));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Spotlight
            _buildProjectSpotlight(context, project),
            const SizedBox(height: 32),
            
            // Financial & Workforce Quick Stats
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'BUDGET',
                    value: currencyFormat.format(project.plannedBudget),
                    icon: Icons.account_balance_wallet_outlined,
                    color: DFColors.primaryStitch,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: workforceAsync.when(
                    data: (attendance) {
                      final presentCount = attendance.where((a) => a.status.name == 'present').length;
                      return _SummaryCard(
                        title: 'SITE FORCE',
                        value: '$presentCount Present',
                        icon: Icons.engineering_outlined,
                        color: DFColors.normal,
                      );
                    },
                    loading: () => const _SummaryLoading(),
                    error: (_, __) => _SummaryCard(title: 'MANPOWER', value: 'Error', icon: Icons.error, color: DFColors.critical),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Critical Alerts Region
            Text('ACTIVE ALERTS', style: DFTextStyles.labelSm),
            const SizedBox(height: 16),
            deviationAsync.when(
              data: (dev) => _buildAlertCard(context, project.id, dev),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Err: $e'),
            ),
            const SizedBox(height: 32),
            
            // Project Actions
            Text('SITE ACTIONS', style: DFTextStyles.labelSm),
            const SizedBox(height: 16),
            _buildActionItem(
              context,
              'View Site Logs',
              'Check daily reports and progress updates.',
              Icons.description_outlined,
              () => context.push('/projects/${project.id}'),
            ),
            _buildActionItem(
              context,
              'Workforce Drilldown',
              'Analyze trade-wise manpower distribution.',
              Icons.groups_outlined,
              () => context.push('/projects/${project.id}/workforce'),
            ),
            _buildActionItem(
              context,
              'Historical Reports',
              'Export material usage and budget PDF reports.',
              Icons.picture_as_pdf_outlined,
              () => context.push('/projects/${project.id}/pdf-preview'),
            ),
            const SizedBox(height: 32),
            
            // Recent Bills Section
            Text('RECENT VENDOR BILLS', style: DFTextStyles.labelSm),
            const SizedBox(height: 16),
            ref.watch(ownerRecentBillsProvider).when(
              data: (bills) {
                if (bills.isEmpty) {
                  return DFCard(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('No digital invoices archived yet.', style: DFTextStyles.caption),
                    ),
                  );
                }
                return Column(
                  children: bills.map((bill) => _buildBillTile(context, bill)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading bills: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillTile(BuildContext context, dynamic bill) {
    return DFCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: DFColors.normal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_long_outlined, color: DFColors.normal, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bill.vendorName, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                Text('${bill.category} • ${DateFormat('MMM dd').format(bill.date)}', style: DFTextStyles.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Text('₹${NumberFormat('#,##,###').format(bill.amount)}', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
        ],
      ),
    );
  }

  Widget _buildProjectSpotlight(BuildContext context, ProjectModel project) {
    return DFCard(
      onTap: () => context.push('/projects/${project.id}'),
      padding: const EdgeInsets.all(24),
      color: DFColors.primaryStitch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: Text(project.status.name.toUpperCase(), 
                  style: DFTextStyles.labelSm.copyWith(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Text(project.name, style: DFTextStyles.screenTitle.copyWith(color: Colors.white, fontSize: 22)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Colors.white70, size: 12),
              const SizedBox(width: 4),
              Text(project.location, style: DFTextStyles.body.copyWith(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(BuildContext context, String projectId, Map<String, dynamic>? devData) {
    if (devData == null || devData['overallSeverity'] == 'normal') {
      return DFCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: DFColors.normal),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('All benchmarks normal', style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  Text('Resource metrics are within estimated bounds.', style: DFTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final severity = devData['overallSeverity'] == 'critical' ? 'CRITICAL' : 'WARNING';
    final color = devData['overallSeverity'] == 'critical' ? DFColors.critical : DFColors.warning;

    return DFCard(
      onTap: () => context.push('/projects/$projectId'),
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(devData['overallSeverity'] == 'critical' ? Icons.error_outline : Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$severity: ${devData['reason'] ?? 'Asset Overrun'}', 
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(devData['aiInsightSummary'] ?? 'Immediate site audit recommended.', 
                  style: DFTextStyles.caption.copyWith(color: color.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(BuildContext context, String title, String subtitle, IconData icon, VoidCallback onTap) {
    return DFCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: DFColors.primaryStitch, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                Text(subtitle, style: DFTextStyles.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: DFColors.outlineVariant, size: 18),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return DFCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(value, style: DFTextStyles.metricLarge.copyWith(fontSize: 18, height: 1.0)),
          const SizedBox(height: 4),
          Text(title, style: DFTextStyles.labelSm.copyWith(fontSize: 9, fontWeight: FontWeight.bold, color: DFColors.textSecondary)),
        ],
      ),
    );
  }
}

class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();
  @override
  Widget build(BuildContext context) {
    return const DFCard(
      padding: EdgeInsets.all(20),
      child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}
