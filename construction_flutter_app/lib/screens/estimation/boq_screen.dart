import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../services/boq_pdf.dart';
import '../../models/assembly.dart';
import '../../models/rate_library.dart';
import '../../models/cost_adjustments.dart';
import '../../models/estimation_profile.dart';
import '../../services/estimation_profile_service.dart';
import '../../services/assembly_engine.dart';
import '../../services/assembly_set_service.dart';
import '../../services/rate_library_service.dart';
import '../../services/cost_adjustments_service.dart';

/// Phase 2d — detailed, assembly-based Bill of Quantities. Renders each
/// assembly expanded into costed line items, and (in edit mode) lets the user
/// tune the per-driver coefficients of each recipe, persisted per project.
class BoqScreen extends ConsumerStatefulWidget {
  final String projectId;
  final Map<String, dynamic> geometry;
  final String brickType;
  final String projectName;
  const BoqScreen({
    super.key,
    required this.projectId,
    required this.geometry,
    this.brickType = 'modular_mix',
    this.projectName = 'Project',
  });

  @override
  ConsumerState<BoqScreen> createState() => _BoqScreenState();
}

class _BoqScreenState extends ConsumerState<BoqScreen> {
  bool _editing = false;
  bool _saving = false;
  final Map<String, TextEditingController> _coeffCtrls = {};
  bool _seeded = false;

  final TextEditingController _wasteCtrl = TextEditingController();
  final TextEditingController _ohpCtrl = TextEditingController();
  final TextEditingController _contCtrl = TextEditingController();
  bool _adjSeeded = false;

  @override
  void dispose() {
    for (final c in _coeffCtrls.values) {
      c.dispose();
    }
    _wasteCtrl.dispose();
    _ohpCtrl.dispose();
    _contCtrl.dispose();
    super.dispose();
  }

  void _seedAdj(CostAdjustments a) {
    _wasteCtrl.text = _num(a.wastePercent);
    _ohpCtrl.text = _num(a.overheadProfitPercent);
    _contCtrl.text = _num(a.contingencyPercent);
    _adjSeeded = true;
  }

  CostAdjustments _readAdj() => CostAdjustments(
        wastePercent: double.tryParse(_wasteCtrl.text.trim()) ?? 0,
        overheadProfitPercent: double.tryParse(_ohpCtrl.text.trim()) ?? 0,
        contingencyPercent: double.tryParse(_contCtrl.text.trim()) ?? 0,
      );

  void _seed(AssemblySet set) {
    for (final a in set.assemblies) {
      for (final c in a.components) {
        _coeffCtrls['${a.id}.${c.itemKey}'] =
            TextEditingController(text: _num(c.coefficient));
      }
    }
    _seeded = true;
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _inr(num v) {
    final s = v.round().abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}₹${b.toString()}';
  }

  Future<void> _save(AssemblySet base) async {
    setState(() => _saving = true);
    var set = base;
    for (final a in base.assemblies) {
      final next = <AssemblyComponent>[];
      for (final c in a.components) {
        final raw = _coeffCtrls['${a.id}.${c.itemKey}']?.text.trim() ?? '';
        final v = double.tryParse(raw);
        next.add(v != null ? c.copyWith(coefficient: v) : c);
      }
      set = set.withAssembly(a.withComponents(next));
    }
    try {
      await ref.read(assemblySetServiceProvider).save(widget.projectId, set);
      await ref
          .read(costAdjustmentsServiceProvider)
          .save(widget.projectId, _readAdj());
      ref.invalidate(projectAssemblySetProvider(widget.projectId));
      ref.invalidate(projectCostAdjustmentsProvider(widget.projectId));
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Recipes saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _export(
      RateLibrary rates, AssemblySet set, CostAdjustments adj) async {
    final boq = AssemblyEngine.build(widget.geometry, set, rates,
        brickType: widget.brickType, wasteFactor: adj.wasteFactor);
    if (boq.assemblies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export — no geometry.')),
      );
      return;
    }
    try {
      final bytes = await BoqPdf.build(
          projectName: widget.projectName, boq: boq, adj: adj);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'BOQ_${widget.projectName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratesAsync = ref.watch(projectRateLibraryProvider(widget.projectId));
    final setAsync = ref.watch(projectAssemblySetProvider(widget.projectId));
    final adjAsync = ref.watch(projectCostAdjustmentsProvider(widget.projectId));
    final profileAsync =
        ref.watch(projectEstimationProfileProvider(widget.projectId));

    // Apply the finish package + regional factors so BOQ costs match the
    // results screen.
    final profile = profileAsync.valueOrNull ?? const EstimationProfile();
    final effRates =
        profile.apply(ratesAsync.valueOrNull ?? RateLibrary.defaults());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detailed BOQ'),
        actions: [
          if (setAsync.hasValue && ratesAsync.hasValue && adjAsync.hasValue) ...[
            if (!_editing)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export BOQ PDF',
                onPressed: () => _export(
                  effRates,
                  setAsync.valueOrNull ?? AssemblySet.defaults(),
                  adjAsync.valueOrNull ?? const CostAdjustments(),
                ),
              ),
            IconButton(
              icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
              tooltip: _editing ? 'Cancel' : 'Edit recipes & adjustments',
              onPressed: () => setState(() => _editing = !_editing),
            ),
          ],
        ],
      ),
      body: (ratesAsync.isLoading ||
              setAsync.isLoading ||
              adjAsync.isLoading ||
              profileAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : _body(
              effRates,
              setAsync.valueOrNull ?? AssemblySet.defaults(),
              adjAsync.valueOrNull ?? const CostAdjustments(),
            ),
      bottomNavigationBar: _editing
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () => _save(setAsync.valueOrNull ?? AssemblySet.defaults()),
                style:
                    ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('SAVE RECIPES'),
              ),
            )
          : null,
    );
  }

  Widget _body(RateLibrary rates, AssemblySet set, CostAdjustments adj) {
    if (!_seeded) _seed(set);
    if (!_adjSeeded) _seedAdj(adj);
    // In edit mode reflect the live field values so the summary updates as you
    // type; otherwise use the saved adjustments.
    final effAdj = _editing ? _readAdj() : adj;
    final boq = AssemblyEngine.build(widget.geometry, set, rates,
        brickType: widget.brickType, wasteFactor: effAdj.wasteFactor);

    if (boq.assemblies.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No geometry available to build a BOQ.',
            textAlign: TextAlign.center),
      ));
    }

    final double subtotal = boq.grandTotal; // already incl. wastage
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final ar in boq.assemblies) _assemblyCard(ar),
        const SizedBox(height: 8),
        if (_editing) _adjustmentsEditor(),
        _summaryCard(subtotal, effAdj),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _summaryCard(double subtotal, CostAdjustments adj) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                      fontSize: bold ? 18 : 14,
                      color: bold ? Colors.indigo : null)),
            ],
          ),
        );
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            row('Materials subtotal (incl. ${_num(adj.wastePercent)}% wastage)',
                _inr(subtotal)),
            row('Overhead & Profit (${_num(adj.overheadProfitPercent)}%)',
                _inr(adj.overheadAmount(subtotal))),
            row('Contingency (${_num(adj.contingencyPercent)}%)',
                _inr(adj.contingencyAmount(subtotal))),
            const Divider(),
            row('PROJECT TOTAL', _inr(adj.finalTotal(subtotal)), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _adjustmentsEditor() {
    Widget field(String label, TextEditingController c) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}), // live summary update
              decoration: InputDecoration(
                labelText: label,
                suffixText: '%',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cost adjustments',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              field('Wastage', _wasteCtrl),
              field('OH & P', _ohpCtrl),
              field('Contingency', _contCtrl),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _assemblyCard(AssemblyResult ar) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(ar.assembly.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${ar.assembly.driverLabel}: '
                    '${ar.driverValue.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const Divider(),
            for (int i = 0; i < ar.lines.length; i++)
              _line(ar, ar.lines[i]),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Subtotal  ${_inr(ar.subtotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(AssemblyResult ar, BoqLine l) {
    final bool isBrick = l.itemKey != 'cement' &&
        l.itemKey != 'steel' &&
        l.itemKey != 'sand' &&
        l.itemKey != 'aggregate' &&
        ar.assembly.id == 'brick_masonry';
    if (!_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                flex: 4,
                child: Text('${l.label}\n${l.quantity} ${l.unit} × ₹${_num(l.rate)}',
                    style: const TextStyle(fontSize: 13))),
            Expanded(
                flex: 2,
                child: Text(_inr(l.amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }
    // Edit mode: tune the per-driver coefficient.
    final ctrl = _coeffCtrls['${ar.assembly.id}.${l.itemKey}'] ??
        _coeffCtrls['${ar.assembly.id}.bricks'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(l.label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              enabled: !isBrick, // bricks coeff is set by the brick type
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                helperText: isBrick ? 'by brick type' : 'per ${ar.assembly.driver}',
                helperStyle: const TextStyle(fontSize: 10),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
