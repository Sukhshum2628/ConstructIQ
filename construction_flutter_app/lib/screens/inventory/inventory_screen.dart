import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/resource_log_model.dart';
import '../../providers/logging_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/material_rates.dart';
import '../../utils/design_tokens.dart';

class _Stock {
  final String key;
  final double received;
  final double consumed;
  _Stock(this.key, this.received, this.consumed);
  double get onHand => received - consumed;
}

class InventoryScreen extends ConsumerWidget {
  final String projectId;
  const InventoryScreen({super.key, required this.projectId});

  List<_Stock> _compute(List<ResourceLogModel> logs) {
    final received = <String, double>{};
    final consumed = <String, double>{};
    for (final log in logs) {
      log.materialReceived.forEach((k, v) {
        final c = MaterialRates.canonKey(k);
        received[c] = (received[c] ?? 0) + v;
      });
      log.materialUsage.forEach((k, v) {
        if (v == 0) return;
        final c = MaterialRates.canonKey(k);
        consumed[c] = (consumed[c] ?? 0) + v;
      });
    }
    final keys = {...received.keys, ...consumed.keys}.toList()
      ..sort((a, b) => MaterialRates.catalogLabel(a).compareTo(MaterialRates.catalogLabel(b)));
    return keys.map((k) => _Stock(k, received[k] ?? 0, consumed[k] ?? 0)).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectLogsProvider(projectId));
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: const Text('Inventory & Stock'),
        backgroundColor: DFColors.surface,
        foregroundColor: DFColors.textPrimary,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DFColors.primary,
        icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
        label: const Text('Record Delivery', style: TextStyle(color: Colors.white)),
        onPressed: () => _recordDelivery(context, ref),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (logs) {
          final stock = _compute(logs);
          if (stock.isEmpty) return _emptyState(context, ref);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('ON-HAND = DELIVERED − CONSUMED',
                  style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.0, color: DFColors.primary)),
              const SizedBox(height: 8),
              ...stock.map(_stockCard),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 56, color: DFColors.outline),
              const SizedBox(height: 12),
              Text('No stock activity yet', style: DFTextStyles.cardTitle),
              const SizedBox(height: 6),
              Text(
                'Record deliveries here, and daily usage in the resource log. '
                'On-hand stock = delivered − consumed.',
                textAlign: TextAlign.center,
                style: DFTextStyles.caption,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _recordDelivery(context, ref),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Record a delivery'),
              ),
            ],
          ),
        ),
      );

  Widget _stockCard(_Stock s) {
    final unit = MaterialRates.catalogUnit(s.key);
    final (statusLabel, statusColor) = s.received == 0 && s.consumed > 0
        ? ('No delivery logged', DFColors.warning)
        : (s.onHand < -0.0001
            ? ('Short', DFColors.critical)
            : (s.onHand < 0.0001 ? ('Depleted', DFColors.outline) : ('In stock', DFColors.success)));
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(MaterialRates.catalogLabel(s.key), style: DFTextStyles.cardTitle),
                const SizedBox(height: 4),
                Text('Delivered ${fmt(s.received)} · Used ${fmt(s.consumed)} $unit',
                    style: DFTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmt(s.onHand),
                      style: DFTextStyles.metricLarge.copyWith(color: statusColor)),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(unit, style: DFTextStyles.caption),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _recordDelivery(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _DeliveryDialog(
        onSave: (key, qty) async {
          final uid = ref.read(authStateChangesProvider).value?.uid ?? 'unknown';
          final log = ResourceLogModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            projectId: projectId,
            loggedBy: uid,
            date: DateTime.now(),
            materialUsage: const {},
            materialReceived: {key: qty},
            equipmentList: const [],
            laborHours: 0,
            notes: 'Delivery: ${MaterialRates.catalogLabel(key)}',
            weatherCondition: 'N/A',
            createdAt: DateTime.now(),
          );
          await ref.read(loggingServiceProvider).addLog(log);
          ref.invalidate(projectLogsProvider(projectId));
        },
      ),
    );
  }
}

class _DeliveryDialog extends StatefulWidget {
  final Future<void> Function(String key, double qty) onSave;
  const _DeliveryDialog({required this.onSave});

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  String? _key;
  final _qty = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qty.text.trim());
    if (_key == null || qty == null || qty <= 0) return;
    setState(() => _saving = true);
    await widget.onSave(_key!, qty);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unit = _key == null ? '' : MaterialRates.catalogUnit(_key!);
    return AlertDialog(
      title: const Text('Record Delivery'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _key,
            decoration: const InputDecoration(labelText: 'Material', border: OutlineInputBorder()),
            items: MaterialRates.allMaterialKeys
                .map((k) => DropdownMenuItem(
                      value: k,
                      child: Text('${MaterialRates.catalogLabel(k)} (${MaterialRates.catalogUnit(k)})',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _key = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Quantity received${unit.isEmpty ? '' : ' ($unit)'}',
                border: const OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
