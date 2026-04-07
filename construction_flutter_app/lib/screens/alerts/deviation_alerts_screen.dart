import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/deviation_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_pill.dart';
import '../../widgets/df_button.dart';

class DeviationAlertsScreen extends ConsumerWidget {
  const DeviationAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviationsAsync = ref.watch(allDeviationsProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          _buildSummaryHero(),
          deviationsAsync.when(
            data: (deviations) => SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _AlertItem(deviation: deviations[index]),
                  childCount: deviations.length,
                ),
              ),
            ),
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('ERR: $e'))),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: DFColors.background,
      elevation: 0,
      centerTitle: false,
      title: Text('DEVIATION MONITOR', 
        style: DFTextStyles.caption.copyWith(
          color: DFColors.primary, 
          fontWeight: FontWeight.bold, 
          letterSpacing: 2.0
        )
      ),
      actions: [
        IconButton(icon: const Icon(Icons.tune, color: DFColors.textPrimary), onPressed: () {}),
        const SizedBox(width: DFSpacing.lg),
      ],
    );
  }

  Widget _buildSummaryHero() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(DFSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: DFColors.criticalBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DFColors.critical.withValues(alpha: 0.5), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: DFColors.critical, size: 28),
                      const SizedBox(width: 12),
                      Text('CRITICAL DEVIATION DETECTED', 
                        style: DFTextStyles.cardTitle.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('BLOCK-A RESIDENTIAL COMPLEX • CEMENT USAGE 52% OVER ESTIMATE', 
                    style: DFTextStyles.body.copyWith(color: DFColors.critical, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  const DFPill(label: 'IMMEDIATE ACTION REQUIRED', severity: 'critical'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('ACTIVE ALERTS & DEVIATIONS', 
              style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.textSecondary, letterSpacing: 1.2)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final Map<String, dynamic> deviation;
  const _AlertItem({required this.deviation});

  @override
  Widget build(BuildContext context) {
    final severity = deviation['overallSeverity'] as String? ?? 'normal';
    final prob = (deviation['mlOverrunProbability'] as num? ?? 0.0) * 100;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DFCard(
        padding: const EdgeInsets.all(20),
        hasShadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(deviation['category']?.toString().toUpperCase() ?? 'STRUCTURAL', 
                  style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.primary)),
                DFPill(label: severity.toUpperCase(), severity: severity),
              ],
            ),
            const SizedBox(height: 12),
            Text(deviation['description'] ?? 'UNSPECIFIED ANOMALY', 
              style: DFTextStyles.cardTitle.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('ML ANALYSIS: ${prob.toStringAsFixed(1)}% PROBABILITY OF COST OVERRUN', 
              style: DFTextStyles.caption),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DFButton(
                    label: 'Acknowledge',
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DFButton(
                    label: 'View Logs',
                    outlined: true,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
