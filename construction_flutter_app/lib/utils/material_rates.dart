class MaterialRates {
  /// Approximate CPWD/Market rates in INR (₹)
  static const Map<String, Map<String, dynamic>> defaultRates = {
    'cement': {'rate': 400.0, 'unit': 'Bag'}, 
    'bricks': {'rate': 12.0, 'unit': 'Nos'},  
    'steel': {'rate': 70.0, 'unit': 'Kg'},   
    'sand': {'rate': 95.0, 'unit': 'cu.ft'},  
    'aggregate': {'rate': 140.0, 'unit': 'cu.ft'}, 
    'painting': {'rate': 55.0, 'unit': 'sq.ft'},
    'flooring': {'rate': 210.0, 'unit': 'sq.ft'},
    'plastering': {'rate': 95.0, 'unit': 'sq.ft'},
  };

  static double getRateForMaterial(String materialName) {
    final nameNormalized = materialName.toLowerCase().trim();
    
    for (final entry in defaultRates.entries) {
      if (nameNormalized.contains(entry.key)) {
        return entry.value['rate'] as double;
      }
    }
    return 0.0;
  }

  static String getRateUnitForMaterial(String materialName) {
    final nameNormalized = materialName.toLowerCase().trim();
    for (final entry in defaultRates.entries) {
      if (nameNormalized.contains(entry.key)) {
        return entry.value['unit'] as String;
      }
    }
    return '';
  }

  static double calculateEstimatedCost(String materialName, double quantity) {
    final effectiveQty = getQuantityInRateUnit(materialName, quantity);
    final rate = getRateForMaterial(materialName);
    return rate * effectiveQty;
  }

  static double getQuantityInRateUnit(String materialName, double quantity) {
    final nameNormalized = materialName.toLowerCase().trim();
    
    // Conversion for materials where backend gives m3 but rates are per cu.ft
    if (nameNormalized.contains('sand') || nameNormalized.contains('aggregate')) {
      // 1 m3 = 35.3147 cubic feet
      return quantity * 35.3147;
    }

    return quantity;
  }

  /// Interior / finishing materials — approximate Indian market MATERIAL rates
  /// (₹). Keyed by the item keys produced by EstimationEngine.calculateInterior.
  static const Map<String, Map<String, dynamic>> interiorRates = {
    'floor_tiles':     {'rate': 650.0,  'unit': 'm2',  'label': 'Floor Tiles'},
    'skirting':        {'rate': 120.0,  'unit': 'm',   'label': 'Skirting'},
    'wall_dado_tiles': {'rate': 550.0,  'unit': 'm2',  'label': 'Wall / Dado Tiles'},
    'wall_putty':      {'rate': 650.0,  'unit': 'bag', 'label': 'Wall Putty'},
    'primer':          {'rate': 180.0,  'unit': 'L',   'label': 'Primer'},
    'emulsion_paint':  {'rate': 320.0,  'unit': 'L',   'label': 'Emulsion Paint'},
    'wc':              {'rate': 6000.0, 'unit': 'nos', 'label': 'WC / Toilet'},
    'washbasin':       {'rate': 3000.0, 'unit': 'nos', 'label': 'Wash Basin'},
    'shower_tap_set':  {'rate': 2800.0, 'unit': 'nos', 'label': 'Shower & Tap Set'},
    'kitchen_sink':    {'rate': 4000.0, 'unit': 'nos', 'label': 'Kitchen Sink'},
    'light_points':    {'rate': 650.0,  'unit': 'nos', 'label': 'Light Points'},
    'fan_points':      {'rate': 1800.0, 'unit': 'nos', 'label': 'Fan Points'},
    'socket_points':   {'rate': 450.0,  'unit': 'nos', 'label': 'Socket Points'},
    'switch_boards':   {'rate': 1200.0, 'unit': 'nos', 'label': 'Switch Boards'},
  };

  /// Bulk structural materials for the inventory/delivery catalog.
  static const Map<String, Map<String, String>> structuralCatalog = {
    'cement': {'label': 'Cement', 'unit': 'Bags'},
    'bricks': {'label': 'Bricks', 'unit': 'Nos'},
    'steel': {'label': 'Steel', 'unit': 'kg'},
    'sand': {'label': 'Sand', 'unit': 'm3'},
    'aggregate': {'label': 'Aggregate', 'unit': 'm3'},
  };

  // Logs historically store steel under 'rebar'; treat it as 'steel'.
  static String _canon(String key) => key == 'rebar' ? 'steel' : key;

  static String catalogLabel(String key) {
    final k = _canon(key);
    return structuralCatalog[k]?['label'] ??
        (interiorRates[k]?['label'] as String?) ??
        k;
  }

  static String catalogUnit(String key) {
    final k = _canon(key);
    return structuralCatalog[k]?['unit'] ??
        (interiorRates[k]?['unit'] as String?) ??
        '';
  }

  static String canonKey(String key) => _canon(key);

  /// All selectable materials (structural + interior) for a delivery entry.
  static List<String> get allMaterialKeys =>
      [...structuralCatalog.keys, ...interiorRates.keys];

  static String interiorLabel(String key) =>
      interiorRates[key]?['label'] as String? ?? key;

  static double interiorRate(String key) =>
      interiorRates[key]?['rate'] as double? ?? 0.0;

  static double interiorCost(String key, double quantity) =>
      interiorRate(key) * quantity;

  // ── Phase 1: selectable material specs ───────────────────────────────────

  /// Brick/block variants. `perM2` = units per m² of wall, `rate` = ₹/unit.
  /// AAC is a block (600×200×100mm) so far fewer units per m².
  static const Map<String, Map<String, dynamic>> brickTypes = {
    'modular_mix': {'perM2': 90.0, 'rate': 12.0, 'unit': 'Nos', 'label': 'Modular (9"+4.5" mix)'},
    'wirecut':     {'perM2': 100.0, 'rate': 16.0, 'unit': 'Nos', 'label': 'Wirecut'},
    'flyash':      {'perM2': 90.0, 'rate': 9.0,  'unit': 'Nos', 'label': 'Fly-ash'},
    'aac_block':   {'perM2': 8.0,  'rate': 65.0, 'unit': 'Nos', 'label': 'AAC Block'},
  };

  static double brickPerM2(String t) =>
      (brickTypes[t]?['perM2'] as num?)?.toDouble() ?? 90.0;
  static double brickRate(String t) =>
      (brickTypes[t]?['rate'] as num?)?.toDouble() ?? 12.0;
  static String brickUnit(String t) => brickTypes[t]?['unit'] as String? ?? 'Nos';
  static String brickLabel(String t) => brickTypes[t]?['label'] as String? ?? t;

  /// Floor/dado tile sizes. Area is unchanged by size; the size only changes
  /// how many boxes you buy (and the per-m² rate, set in interiorRates).
  static const Map<String, Map<String, dynamic>> tileSizes = {
    '300x300':  {'tilesPerBox': 11, 'm2PerBox': 1.0,  'label': '300×300 mm'},
    '600x600':  {'tilesPerBox': 4,  'm2PerBox': 1.44, 'label': '600×600 mm'},
    '800x800':  {'tilesPerBox': 3,  'm2PerBox': 1.92, 'label': '800×800 mm'},
    '1200x600': {'tilesPerBox': 2,  'm2PerBox': 1.44, 'label': '1200×600 mm'},
  };

  static double tileM2PerBox(String s) =>
      (tileSizes[s]?['m2PerBox'] as num?)?.toDouble() ?? 1.44;
  static String tileLabel(String s) => tileSizes[s]?['label'] as String? ?? s;
}
