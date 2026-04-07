import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/design_tokens.dart';
import '../../providers/deviation_provider.dart';

class NotificationCentreScreen extends ConsumerStatefulWidget {
  const NotificationCentreScreen({super.key});

  @override
  ConsumerState<NotificationCentreScreen> createState() => _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends ConsumerState<NotificationCentreScreen> {
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Critical', 'Warning', 'Info'];
  final Set<String> _readIds = {};

  @override
  Widget build(BuildContext context) {
    final allDevsAsync = ref.watch(allDeviationsProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background.withValues(alpha: 0.8),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DFColors.textSecondary),
          onPressed: () => context.pop(),
        ),
        title: Text('Alerts', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                // Mark all as read
                allDevsAsync.whenData((devs) {
                  for (var d in devs) {
                    final id = d['deviationId'] as String? ?? '';
                    if (id.isNotEmpty) _readIds.add(id);
                  }
                });
              });
            },
            child: Text('Mark all read',
              style: DFTextStyles.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: DFColors.primary),
            ),
          ),
          const SizedBox(width: DFSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg),
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isActive = filter == _activeFilter;
                  return GestureDetector(
                    onTap: () => setState(() => _activeFilter = filter),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive ? DFColors.primary : DFColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: isActive ? [const BoxShadow(color: Color.fromRGBO(0,0,0,0.05), blurRadius: 4, offset: Offset(0,2))] : null,
                        ),
                        child: Text(
                          filter,
                          style: DFTextStyles.body.copyWith(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                            color: isActive ? Colors.white : DFColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Notification List
          Expanded(
            child: allDevsAsync.when(
              data: (deviations) {
                // Map severity filter
                final filteredDevs = _activeFilter == 'All'
                    ? deviations
                    : deviations.where((d) {
                        final severity = d['overallSeverity'] as String? ?? 'normal';
                        if (_activeFilter == 'Critical') return severity == 'critical';
                        if (_activeFilter == 'Warning') return severity == 'warning';
                        if (_activeFilter == 'Info') return severity == 'normal';
                        return true;
                      }).toList();

                if (filteredDevs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg, vertical: DFSpacing.md),
                  itemCount: filteredDevs.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: DFSpacing.md),
                  itemBuilder: (context, index) {
                    if (index == filteredDevs.length) {
                      return _buildEmptyState();
                    }
                    return _buildNotificationCard(filteredDevs[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primary)),
              error: (e, _) => Center(child: Text('Error loading alerts: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> devData) {
    final severity = devData['overallSeverity'] as String? ?? 'normal';
    final deviationId = devData['deviationId'] as String? ?? '';
    final isUnread = !_readIds.contains(deviationId);
    final aiSummary = devData['aiInsightSummary'] as String? ?? 'No details available.';
    final mlProb = (devData['mlOverrunProbability'] as num?)?.toDouble() ?? 0.0;
    final generatedAt = devData['generatedAt'] as Timestamp?;

    // Build title from severity and probability
    String title;
    switch (severity) {
      case 'critical':
        title = 'Critical Deviation: ${(mlProb * 100).toStringAsFixed(0)}% Overrun Risk';
        break;
      case 'warning':
        title = 'Warning: Material Usage Anomaly Detected';
        break;
      default:
        title = 'Project Status: Within Expected Range';
    }

    // Time ago
    String timeAgo = '';
    if (generatedAt != null) {
      final diff = DateTime.now().difference(generatedAt.toDate());
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}h ago';
      } else {
        timeAgo = '${diff.inDays}d ago';
      }
    }

    final Color stripColor;
    final Color badgeBg;
    final Color badgeTextColor;
    final IconData badgeIcon;
    final String badgeLabel;

    switch (severity) {
      case 'critical':
        stripColor = const Color(0xFFB10010);
        badgeBg = const Color(0xFFB10010);
        badgeTextColor = Colors.white;
        badgeIcon = Icons.error;
        badgeLabel = 'CRITICAL';
        break;
      case 'warning':
        stripColor = DFColors.secondaryContainer;
        badgeBg = DFColors.secondaryContainer;
        badgeTextColor = const Color(0xFF2A1700);
        badgeIcon = Icons.warning;
        badgeLabel = 'WARNING';
        break;
      default:
        stripColor = DFColors.primaryContainer;
        badgeBg = DFColors.primaryContainer;
        badgeTextColor = Colors.white;
        badgeIcon = Icons.info;
        badgeLabel = 'INFO';
    }

    return GestureDetector(
      onTap: () {
        // Mark as read on tap
        if (deviationId.isNotEmpty) {
          setState(() => _readIds.add(deviationId));
        }
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isUnread ? DFColors.primaryLight : DFColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0,0,0,0.04), blurRadius: 8, offset: Offset(0,2))],
        ),
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: stripColor)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(badgeIcon, size: 12, color: badgeTextColor),
                                const SizedBox(width: 4),
                                Text(badgeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: badgeTextColor, letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: DFColors.primaryContainer, shape: BoxShape.circle)),
                          ]
                        ],
                      ),
                      Text(timeAgo, style: DFTextStyles.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: DFColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(title, style: DFTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(aiSummary, style: DFTextStyles.body.copyWith(fontSize: 13, color: DFColors.textSecondary, height: 1.5), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Opacity(
        opacity: 0.4,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: DFColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none, size: 40, color: DFColors.textSecondary),
            ),
            const SizedBox(height: DFSpacing.lg),
            Text('All clear', style: DFTextStyles.body.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: DFSpacing.sm),
            SizedBox(
              width: 240,
              child: Text(
                "You're caught up with all site alerts and project updates.",
                textAlign: TextAlign.center,
                style: DFTextStyles.body.copyWith(fontSize: 13, color: DFColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
