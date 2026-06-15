import '../utils/material_rates.dart';

/// A single editable rate-library entry: ₹ material (supply) rate per unit,
/// plus an optional labour rate per unit (used by Phase 2 assemblies).
class RateItem {
  final String key;
  final String label;
  final String unit;
  final double materialRate;
  final double labourRate;

  const RateItem({
    required this.key,
    required this.label,
    required this.unit,
    required this.materialRate,
    this.labourRate = 0,
  });

  double get totalRate => materialRate + labourRate;

  RateItem copyWith({double? materialRate, double? labourRate}) => RateItem(
        key: key,
        label: label,
        unit: unit,
        materialRate: materialRate ?? this.materialRate,
        labourRate: labourRate ?? this.labourRate,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'unit': unit,
        'materialRate': materialRate,
        'labourRate': labourRate,
      };

  factory RateItem.fromJson(String key, Map<String, dynamic> j) => RateItem(
        key: key,
        label: (j['label'] as String?) ?? key,
        unit: (j['unit'] as String?) ?? '',
        materialRate: (j['materialRate'] as num?)?.toDouble() ?? 0,
        labourRate: (j['labourRate'] as num?)?.toDouble() ?? 0,
      );
}

/// Per-project editable rate library. Starts from app defaults (derived from
/// `MaterialRates`) and is overridden by any per-project saved rates.
class RateLibrary {
  final Map<String, RateItem> items;

  const RateLibrary(this.items);

  RateItem? rateFor(String key) => items[MaterialRates.canonKey(key)];

  /// Supply rate for a key, falling back to 0 if unknown.
  double materialRate(String key) => rateFor(key)?.materialRate ?? 0;

  /// Returns a copy with one item's rates replaced.
  RateLibrary withItem(String key, RateItem item) {
    final next = Map<String, RateItem>.from(items)..[key] = item;
    return RateLibrary(next);
  }

  /// Only the items that differ from defaults — what we persist per project.
  Map<String, dynamic> toOverridesJson() {
    final defaults = RateLibrary.defaults().items;
    final out = <String, dynamic>{};
    items.forEach((k, v) {
      final d = defaults[k];
      if (d == null ||
          d.materialRate != v.materialRate ||
          d.labourRate != v.labourRate) {
        out[k] = v.toJson();
      }
    });
    return out;
  }

  /// Defaults merged with per-project overrides loaded from Firestore.
  factory RateLibrary.fromOverrides(Map<String, dynamic>? overrides) {
    final base = Map<String, RateItem>.from(RateLibrary.defaults().items);
    if (overrides != null) {
      overrides.forEach((k, v) {
        if (v is Map) {
          final existing = base[k];
          final loaded = RateItem.fromJson(k, Map<String, dynamic>.from(v));
          // Keep default label/unit if the override only carried rates.
          base[k] = RateItem(
            key: k,
            label: existing?.label ?? loaded.label,
            unit: existing?.unit ?? loaded.unit,
            materialRate: loaded.materialRate,
            labourRate: loaded.labourRate,
          );
        }
      });
    }
    return RateLibrary(base);
  }

  /// App-wide default rates, assembled from the existing catalogs so there is a
  /// single source of truth for the starting numbers.
  factory RateLibrary.defaults() {
    final m = <String, RateItem>{};
    void put(String k, String label, String unit, double rate) =>
        m[k] = RateItem(key: k, label: label, unit: unit, materialRate: rate);

    // Bulk structural materials.
    put('cement', 'Cement', 'Bag', 400);
    put('steel', 'Steel', 'kg', 70);
    put('sand', 'Sand', 'cu.ft', 95);
    put('aggregate', 'Aggregate', 'cu.ft', 140);

    // Brick/block variants (each editable).
    for (final e in MaterialRates.brickTypes.entries) {
      put(e.key, e.value['label'] as String, e.value['unit'] as String,
          (e.value['rate'] as num).toDouble());
    }

    // Interior / finishing items.
    for (final e in MaterialRates.interiorRates.entries) {
      put(e.key, e.value['label'] as String, e.value['unit'] as String,
          (e.value['rate'] as num).toDouble());
    }

    return RateLibrary(m);
  }
}
