import 'dart:math' as math;
import '../models/assembly.dart';
import '../models/rate_library.dart';
import '../utils/material_rates.dart';

/// One costed line in a BOQ: quantity × rate = amount.
class BoqLine {
  final String itemKey;
  final String label;
  final String unit;
  final double quantity;
  final double rate;
  final double amount;
  const BoqLine({
    required this.itemKey,
    required this.label,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.amount,
  });
}

/// An assembly expanded against a project's geometry.
class AssemblyResult {
  final Assembly assembly;
  final double driverValue;
  final List<BoqLine> lines;
  AssemblyResult(this.assembly, this.driverValue, this.lines);
  double get subtotal => lines.fold(0.0, (s, l) => s + l.amount);
}

/// Full bill of quantities for a project.
class BoqResult {
  final List<AssemblyResult> assemblies;
  final Map<String, double> materialRollup; // qty by item key
  BoqResult(this.assemblies, this.materialRollup);
  double get grandTotal =>
      assemblies.fold(0.0, (s, a) => s + a.subtotal);
}

class AssemblyEngine {
  /// Geometry drivers, derived the same way as the legacy engine (wall-area
  /// fallback + opening deductions) so assemblies reproduce current numbers.
  static Map<String, double> drivers(Map<String, dynamic> geometry) {
    double d(String k, [double def = 0]) =>
        (geometry[k] is num) ? (geometry[k] as num).toDouble() : def;

    final double floorArea = d('totalFloorArea');
    double wallArea = d('totalWallArea');
    if (wallArea == 0 && d('totalWallLength') > 0) {
      wallArea = d('totalWallLength') * 3.0;
    }
    if (wallArea == 0 && floorArea > 0) {
      wallArea = 4 * math.sqrt(floorArea) * 1.5 * 3.0;
    }
    final double openings = d('doorCount') * 0.9 * 2.1 + d('windowCount') * 1.2 * 1.2;
    final double netWall = (wallArea - openings) < 0 ? 0.0 : wallArea - openings;

    return {
      'netWallArea': netWall,
      'wallArea': wallArea,
      'floorArea': floorArea,
      'columnCount': d('totalColumnCount'),
      'beamLength': d('beamLength'),
      'stairArea': d('stairArea'),
    };
  }

  /// Expand an assembly set into a costed BOQ.
  static BoqResult build(
    Map<String, dynamic> geometry,
    AssemblySet set,
    RateLibrary rates, {
    String brickType = 'modular_mix',
    double wasteFactor = 1.0, // inflates material quantities (Phase 3)
  }) {
    final dv = drivers(geometry);
    final results = <AssemblyResult>[];
    final rollup = <String, double>{};

    for (final a in set.assemblies) {
      final driverValue = dv[a.driver] ?? 0;
      if (driverValue <= 0) continue; // nothing to cost for this assembly
      final lines = <BoqLine>[];

      for (final c in a.components) {
        // Bricks resolve to the selected brick/block type (its own coefficient
        // and rate); everything else uses its rate-library entry directly.
        final bool isBrick = c.itemKey == 'bricks';
        final String key = isBrick ? brickType : c.itemKey;
        final double coeff =
            isBrick ? MaterialRates.brickPerM2(brickType) : c.coefficient;
        final double qty = coeff * driverValue * wasteFactor;

        final item = rates.rateFor(key);
        final double rate = item?.materialRate ?? 0;
        final String label = isBrick
            ? MaterialRates.brickLabel(brickType)
            : (item?.label ?? key);
        final String unit =
            isBrick ? MaterialRates.brickUnit(brickType) : (item?.unit ?? '');

        // sand/aggregate are m³ but priced per cu.ft.
        final double amount =
            rate * MaterialRates.getQuantityInRateUnit(key, qty);

        lines.add(BoqLine(
          itemKey: key,
          label: label,
          unit: unit,
          quantity: double.parse(qty.toStringAsFixed(2)),
          rate: rate,
          amount: double.parse(amount.toStringAsFixed(2)),
        ));
        rollup[key] = (rollup[key] ?? 0) + qty;
      }
      results.add(AssemblyResult(a, driverValue, lines));
    }
    return BoqResult(results, rollup);
  }
}
