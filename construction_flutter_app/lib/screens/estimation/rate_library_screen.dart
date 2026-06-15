import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rate_library.dart';
import '../../services/rate_library_service.dart';
import '../../utils/material_rates.dart';

/// Per-project editable rate library (Phase 2). Edits the ₹ supply rate of
/// each material; saving persists only the values that differ from defaults.
class RateLibraryScreen extends ConsumerStatefulWidget {
  final String projectId;
  const RateLibraryScreen({super.key, required this.projectId});

  @override
  ConsumerState<RateLibraryScreen> createState() => _RateLibraryScreenState();
}

class _RateLibraryScreenState extends ConsumerState<RateLibraryScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(RateLibrary lib) {
    for (final item in lib.items.values) {
      _controllers[item.key] =
          TextEditingController(text: _fmt(item.materialRate));
    }
    _seeded = true;
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _save(RateLibrary base) async {
    setState(() => _saving = true);
    var lib = base;
    base.items.forEach((key, item) {
      final raw = _controllers[key]?.text.trim() ?? '';
      final val = double.tryParse(raw);
      if (val != null && val != item.materialRate) {
        lib = lib.withItem(key, item.copyWith(materialRate: val));
      }
    });
    try {
      await ref.read(rateLibraryServiceProvider).save(widget.projectId, lib);
      ref.invalidate(projectRateLibraryProvider(widget.projectId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rates saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(projectRateLibraryProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(title: const Text('Project Rates')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (lib) {
          if (!_seeded) _seed(lib);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _group('Structural', ['cement', 'steel', 'sand', 'aggregate'], lib),
              _group('Bricks / Blocks', MaterialRates.brickTypes.keys.toList(), lib),
              _group('Interior / Finishes',
                  MaterialRates.interiorRates.keys.toList(), lib),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton(
          onPressed: _saving || !_seeded
              ? null
              : () => _save(ref.read(projectRateLibraryProvider(widget.projectId))
                  .valueOrNull ??
                  RateLibrary.defaults()),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _saving
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('SAVE RATES'),
        ),
      ),
    );
  }

  Widget _group(String title, List<String> keys, RateLibrary lib) {
    final rows = <Widget>[];
    for (final k in keys) {
      final item = lib.items[k];
      if (item == null || _controllers[k] == null) continue;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(item.label)),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _controllers[k],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  isDense: true,
                  suffixText: '/${item.unit}',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Divider(),
        ...rows,
      ],
    );
  }
}
