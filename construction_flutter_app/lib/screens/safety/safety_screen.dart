import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/site_report_model.dart';
import '../../providers/site_report_provider.dart';
import '../../services/site_report_service.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';

class SafetyScreen extends ConsumerWidget {
  final String projectId;
  const SafetyScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(siteReportsProvider(projectId));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: DFColors.background,
        appBar: AppBar(
          title: const Text('Safety & Quality'),
          backgroundColor: DFColors.surface,
          foregroundColor: DFColors.textPrimary,
          elevation: 0.5,
          bottom: const TabBar(
            labelColor: DFColors.primary,
            tabs: [Tab(text: 'Incidents'), Tab(text: 'Snag / Punch')],
          ),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load: $e')),
          data: (all) {
            return TabBarView(children: [
              _list(context, ref, all.where((r) => r.type == SiteReportType.incident).toList(), SiteReportType.incident),
              _list(context, ref, all.where((r) => r.type == SiteReportType.snag).toList(), SiteReportType.snag),
            ]);
          },
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            backgroundColor: DFColors.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Report', style: TextStyle(color: Colors.white)),
            onPressed: () {
              final isIncident = DefaultTabController.of(ctx).index == 0;
              _openAdd(context, ref, isIncident ? SiteReportType.incident : SiteReportType.snag);
            },
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<SiteReportModel> items, SiteReportType type) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type == SiteReportType.incident ? Icons.health_and_safety_outlined : Icons.checklist_rtl,
                  size: 56, color: DFColors.outline),
              const SizedBox(height: 12),
              Text(type == SiteReportType.incident ? 'No incidents reported' : 'No open snags',
                  style: DFTextStyles.cardTitle),
              const SizedBox(height: 6),
              Text(
                type == SiteReportType.incident
                    ? 'Log safety incidents and near-misses to keep a compliance record.'
                    : 'Track quality defects (punch list) until they are resolved.',
                textAlign: TextAlign.center,
                style: DFTextStyles.caption,
              ),
            ],
          ),
        ),
      );
    }
    final open = items.where((r) => !r.isResolved).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('$open OPEN · ${items.length} TOTAL',
            style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.0, color: DFColors.primary)),
        const SizedBox(height: 8),
        ...items.map((r) => _card(context, ref, r)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, SiteReportModel r) {
    final df = DateFormat('MMM d, yyyy');
    final sevColor = r.severity == ReportSeverity.high
        ? DFColors.critical
        : (r.severity == ReportSeverity.medium ? DFColors.warning : DFColors.outline);
    final statusColor = r.status == ReportStatus.resolved
        ? DFColors.success
        : (r.status == ReportStatus.inProgress ? DFColors.primary : DFColors.warning);
    final statusText = r.status == ReportStatus.resolved
        ? 'Resolved'
        : (r.status == ReportStatus.inProgress ? 'In Progress' : 'Open');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.title, style: DFTextStyles.cardTitle)),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'delete') {
                    ref.read(siteReportServiceProvider).delete(projectId, r.id);
                  } else {
                    ref.read(siteReportServiceProvider).setStatus(projectId, r.id, ReportStatus.values.byName(v));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Mark Open')),
                  PopupMenuItem(value: 'inProgress', child: Text('Mark In Progress')),
                  PopupMenuItem(value: 'resolved', child: Text('Mark Resolved')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                child: const Icon(Icons.more_vert, size: 18, color: DFColors.outline),
              ),
            ],
          ),
          if (r.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(r.description, style: DFTextStyles.caption),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(statusText, statusColor),
              if (r.type == SiteReportType.incident) _chip(r.severity.name.toUpperCase(), sevColor),
              if (r.location.isNotEmpty) _chip(r.location, DFColors.outline, outline: true),
              _chip(df.format(r.createdAt), DFColors.outline, outline: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, {bool outline = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : color.withValues(alpha: 0.12),
          border: outline ? Border.all(color: DFColors.outlineVariant) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: outline ? DFColors.textSecondary : color,
                fontWeight: FontWeight.w600,
                fontSize: 11)),
      );

  void _openAdd(BuildContext context, WidgetRef ref, SiteReportType type) {
    showDialog(
      context: context,
      builder: (_) => _ReportDialog(
        type: type,
        onSave: (title, desc, sev, loc) {
          final uid = ref.read(authStateChangesProvider).value?.uid ?? 'unknown';
          ref.read(siteReportServiceProvider).save(SiteReportModel(
                id: const Uuid().v4(),
                projectId: projectId,
                type: type,
                title: title,
                description: desc,
                severity: sev,
                location: loc,
                reportedBy: uid,
                createdAt: DateTime.now(),
              ));
        },
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  final SiteReportType type;
  final void Function(String title, String desc, ReportSeverity sev, String loc) onSave;
  const _ReportDialog({required this.type, required this.onSave});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  ReportSeverity _sev = ReportSeverity.medium;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _loc.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty) return;
    widget.onSave(_title.text.trim(), _desc.text.trim(), _sev, _loc.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isIncident = widget.type == SiteReportType.incident;
    return AlertDialog(
      title: Text(isIncident ? 'Report Incident' : 'Add Snag'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: isIncident ? 'What happened?' : 'Defect',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Details (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loc,
              decoration: const InputDecoration(labelText: 'Location (e.g. 2nd floor)', border: OutlineInputBorder()),
            ),
            if (isIncident) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<ReportSeverity>(
                initialValue: _sev,
                decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
                items: ReportSeverity.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name.toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => _sev = v ?? ReportSeverity.medium),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
