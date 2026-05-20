import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
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
    final user = ref.watch(currentUserProfileProvider);
    final projectsAsync = ref.watch(userProjectsProvider);
    final recentBillsAsync = ref.watch(ownerRecentBillsProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, ref, user?.name ?? 'Portfolio Owner'),
          
          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) {
                return SliverFillRemaining(child: _buildNoProjectState(context, ref));
              }
              
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPortfolioSummary(projects, recentBillsAsync.value ?? []),
                      const SizedBox(height: 32),
                      
                      _buildSectionHeader('ACTIVE PROJECTS', () => context.push('/projects')),
                      const SizedBox(height: 16),
                      _buildProjectCarousel(context, projects),
                      const SizedBox(height: 32),
                      
                      _buildSectionHeader('PORTFOLIO COMMANDS', null),
                      const SizedBox(height: 16),
                      _buildActionGrid(context),
                      const SizedBox(height: 32),
                      
                      _buildSectionHeader('RECENT TRANSACTIONS', () => null),
                      const SizedBox(height: 16),
                      _buildRecentTransactions(context, recentBillsAsync.value ?? []),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('Error: $e'))),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, WidgetRef ref, String name) {
    return SliverAppBar(
      expandedHeight: 120,
      backgroundColor: DFColors.surface,
      floating: true,
      pinned: true,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        centerTitle: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good morning, ${name.split(' ').first}', 
              style: DFTextStyles.cardTitle.copyWith(fontSize: 18, color: DFColors.textPrimary)),
            Text(DateFormat('EEEE, MMM dd').format(DateTime.now()).toUpperCase(), 
              style: DFTextStyles.labelSm.copyWith(fontSize: 9, letterSpacing: 1.2)),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded, color: DFColors.textSecondary),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: DFColors.critical),
          onPressed: () => ref.read(authServiceProvider).signOut(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildPortfolioSummary(List<ProjectModel> projects, List<dynamic> bills) {
    final currencyFormat = NumberFormat.compactCurrency(symbol: '₹', locale: 'en_IN');
    final totalBudget = projects.fold(0.0, (sum, p) => sum + p.plannedBudget);
    final totalSpent = bills.fold(0.0, (sum, b) => sum + b.amount);
    final progress = totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.0) : 0.0;

    return DFCard(
      padding: const EdgeInsets.all(24),
      color: DFColors.primaryStitch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Portfolio Health', style: DFTextStyles.labelSm.copyWith(color: Colors.white70)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: Text('98% ON TRACK', style: DFTextStyles.labelSm.copyWith(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Spent', style: DFTextStyles.caption.copyWith(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(currencyFormat.format(totalSpent), style: DFTextStyles.metricLarge.copyWith(color: Colors.white)),
                ],
              ),
              const Spacer(),
              Text('of ${currencyFormat.format(totalBudget)} total budget', 
                style: DFTextStyles.caption.copyWith(color: Colors.white70, fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCarousel(BuildContext context, List<ProjectModel> projects) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: projects.length,
        padding: const EdgeInsets.only(right: 16),
        itemBuilder: (context, index) {
          final project = projects[index];
          return Container(
            width: 280,
            margin: const EdgeInsets.only(left: 16),
            child: DFCard(
              onTap: () => context.push('/projects/${project.id}'),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: DFColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(project.status.name.toUpperCase(), 
                          style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold, fontSize: 9)),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: DFColors.outlineVariant),
                    ],
                  ),
                  const Spacer(),
                  Text(project.name, style: DFTextStyles.cardTitle.copyWith(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(project.location, style: DFTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildMiniBadge(Icons.show_chart_rounded, 'Site Stable', DFColors.normal),
                      const SizedBox(width: 12),
                      _buildMiniBadge(Icons.schedule_rounded, '12d left', DFColors.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.6), size: 14),
        const SizedBox(width: 4),
        Text(text, style: DFTextStyles.labelSm.copyWith(fontSize: 10, color: color)),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildActionTile(Icons.analytics_outlined, 'Insights', 'Trade-wise Trends', () {}),
        _buildActionTile(Icons.account_balance_rounded, 'Finances', 'Audit Ledgers', () {}),
        _buildActionTile(Icons.folder_shared_outlined, 'Docs', 'Blueprint Vault', () {}),
        _buildActionTile(Icons.verified_user_outlined, 'Compliance', 'Safety Checks', () {}),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String title, String sub, VoidCallback onTap) {
    return DFCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DFColors.primaryStitch, size: 24),
          const Spacer(),
          Text(title, style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
          Text(sub, style: DFTextStyles.caption.copyWith(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(BuildContext context, List<dynamic> bills) {
    if (bills.isEmpty) {
      return DFCard(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text('No transactions found', style: DFTextStyles.caption)),
      );
    }

    return Column(
      children: bills.take(5).map((bill) => _buildTransactionItem(bill)).toList(),
    );
  }

  Widget _buildTransactionItem(dynamic bill) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: DFCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_rounded, color: DFColors.primaryStitch, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.vendorName, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
                  Text(bill.category, style: DFTextStyles.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${NumberFormat('#,##,###').format(bill.amount)}', 
                  style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
                Text(DateFormat('MMM dd').format(bill.date), style: DFTextStyles.caption.copyWith(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onSeeAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: DFTextStyles.labelSm.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.bold)),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text('View Details', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch)),
          ),
      ],
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
}
