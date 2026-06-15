import 'dart:math' as math;
import '../utils/material_rates.dart';

// On-device port of the backend CPWD estimation engine
// (construction-ai-service/modules/estimation_engine.py).
//
// Pure arithmetic — no model, no network. Computing this on-device removes a
// round-trip to Render, lets estimates work offline, and keeps the server slim.
// Output shape matches the old /api/estimation/estimate response exactly so the
// estimation screens are unaffected.

class EstimationEngine {
  static const double _standardHeight = 3.0; // metres
  static const double _slabThickness = 0.15; // metres

  static double _round(num x, int n) => double.parse(x.toStringAsFixed(n));

  static double _d(Map g, String k, [double dflt = 0]) {
    final v = g[k];
    return v is num ? v.toDouble() : dflt;
  }

  /// CPWD quantity take-off. Returns material quantities + breakdown (no cost).
  static Map<String, dynamic> calculateMaterials(Map<String, dynamic> geometry,
      {String brickType = 'modular_mix'}) {
    final projectType = geometry['projectType'] ?? 'new_build';
    final geo = Map<String, dynamic>.from(geometry);
    final assumptions = <String>[];

    // Derive wall area from wall length if missing.
    if (_d(geo, 'totalWallArea') == 0 && _d(geo, 'totalWallLength') > 0) {
      geo['totalWallArea'] = _d(geo, 'totalWallLength') * _standardHeight;
      assumptions.add(
          'Wall area derived from wall length × ${_standardHeight}m height');
    }
    // Fallback: derive wall area from the footprint when no wall geometry was
    // detected at all. The on-device floor-plan parser returns floor area but
    // often reports wall length as 0, which otherwise collapses bricks and
    // plastering to zero. Estimate wall run as the perimeter of an equivalent
    // square plus an internal-partition allowance, then × storey height.
    if (_d(geo, 'totalWallArea') == 0 && _d(geo, 'totalFloorArea') > 0) {
      final double fa = _d(geo, 'totalFloorArea');
      final double perimeter = 4 * math.sqrt(fa); // equivalent-square external run
      const double internalWallFactor = 1.5; // external + internal partitions
      final double wallRun = perimeter * internalWallFactor;
      geo['totalWallArea'] = wallRun * _standardHeight;
      assumptions.add(
          'Wall area estimated from floor area (no wall geometry detected): '
          '≈${wallRun.toStringAsFixed(1)}m wall run × ${_standardHeight}m height');
    }
    // Derive concrete volume from floor area if missing.
    if (_d(geo, 'concreteVolume') == 0 && _d(geo, 'totalFloorArea') > 0) {
      geo['concreteVolume'] = _d(geo, 'totalFloorArea') * _slabThickness;
      assumptions.add(
          'Concrete volume derived from floor area × ${_slabThickness}m slab thickness');
    }
    if (geo['doorCount'] == null) {
      geo['doorCount'] = 0;
      assumptions.add('Door count not detected — no door deductions applied');
    }
    if (geo['windowCount'] == null) {
      geo['windowCount'] = 0;
      assumptions.add('Window count not detected — no window deductions applied');
    }
    geo['floorCount'] ??= 1;

    final double wallArea = _d(geo, 'totalWallArea');
    final double floorArea = _d(geo, 'totalFloorArea');

    if (projectType == 'renovation') {
      return {
        'projectType': 'renovation',
        'materials': {
          'wall_tiles': {'quantity': _round(wallArea, 1), 'unit': 'm2'},
          'floor_tiles': {'quantity': _round(floorArea, 1), 'unit': 'm2'},
          'paint': {'quantity': _round(wallArea, 1), 'unit': 'm2'},
        },
        'assumptions': assumptions,
        'note': 'Renovation project detected. Showing finish area quantities '
            'instead of structural materials (bricks, cement, steel). '
            'Structural quantities are not applicable for remodel work.',
        'openingDeductions': <String, dynamic>{},
        'breakdown': <String, dynamic>{},
        'zoneBreakdown': <String, dynamic>{},
      };
    }

    final double beamLength = _d(geo, 'beamLength');
    final double stairArea = _d(geo, 'stairArea');
    final double columnCount = _d(geo, 'totalColumnCount');
    final int doorCount = (geo['doorCount'] as num).toInt();
    final int windowCount = (geo['windowCount'] as num).toInt();
    final double height = _d(geo, 'buildingHeight', _standardHeight);

    // Opening deductions (CPWD): door 0.9×2.1, window 1.2×1.2.
    const double doorArea = 0.9 * 2.1;
    const double windowArea = 1.2 * 1.2;
    final double openingArea = doorCount * doorArea + windowCount * windowArea;
    final double netWallArea = (wallArea - openingArea) < 0 ? 0.0 : wallArea - openingArea;

    // Brick masonry (net area). Units per m² of wall come from the selected
    // brick/block type (modular 9"+4.5" mix ≈ 90/m², wirecut ≈ 100, fly-ash
    // ≈ 90, AAC block ≈ 8). Was a hardcoded 190/m² — implied a ~0.38m wall and
    // overstated bricks ~3×.
    final double bricksPerM2 = MaterialRates.brickPerM2(brickType);
    final double totalBricks = netWallArea * bricksPerM2;
    final double cementMasonry = netWallArea * 0.85;
    final double sandMasonry = netWallArea * 0.15;

    // RCC structure.
    final double concreteVol =
        (_d(geo, 'concreteVolume') != 0) ? _d(geo, 'concreteVolume') : floorArea * 0.45;
    final double cementSlab = concreteVol * 8.2;
    final double sandSlab = concreteVol * 0.45;
    final double aggregateSlab = concreteVol * 0.85;
    final double steelSlab = concreteVol * 75.0;

    final double stairVol = stairArea * 0.20;
    final double cementStair = stairVol * 8;
    final double aggregateStair = stairVol * 0.84;

    final double beamVol = beamLength * 0.069;
    final double cementBeam = beamVol * 8;
    final double aggregateBeam = beamVol * 0.84;
    final double steelBeam = beamVol * 7850 * 0.02;

    final double colVol = columnCount * 0.053 * height;
    final double cementCol = colVol * 8;
    final double aggregateCol = colVol * 0.84;
    final double steelCol = colVol * 7850 * 0.03;

    final double plasterArea = wallArea * 1.8;
    final double cementPlaster = plasterArea * 0.11;
    final double sandPlaster = plasterArea * 0.022;

    final double cementScreed = floorArea * 0.044;
    final double sandScreed = floorArea * 0.008;

    final double totalCement = cementMasonry +
        cementSlab +
        cementStair +
        cementBeam +
        cementCol +
        cementPlaster +
        cementScreed;
    final double totalSand = sandMasonry + sandSlab + sandPlaster + sandScreed;
    final double totalAggregate =
        aggregateSlab + aggregateStair + aggregateBeam + aggregateCol;
    final double totalSteel = steelSlab + steelBeam + steelCol;

    // Steel resolved into a bar-bending-style schedule by diameter, derived
    // from the per-element totals using typical RCC ratios:
    //   slab → 8mm (60%) + 10mm (40%); beam → 12mm/16mm (50/50);
    //   column → 16mm/20mm (50/50). Sum equals totalSteel.
    final steelByDiameter = <String, double>{};
    void addBar(String dia, double kg) =>
        steelByDiameter[dia] = (steelByDiameter[dia] ?? 0) + kg;
    addBar('8mm', steelSlab * 0.6);
    addBar('10mm', steelSlab * 0.4);
    addBar('12mm', steelBeam * 0.5);
    addBar('16mm', steelBeam * 0.5 + steelCol * 0.5);
    addBar('20mm', steelCol * 0.5);
    final steelSchedule =
        steelByDiameter.map((k, v) => MapEntry(k, _round(v, 1)));

    return {
      'materials': {
        'cement': {'quantity': _round(totalCement, 1), 'unit': 'bags'},
        'bricks': {
          'quantity': totalBricks.toInt(),
          'unit': MaterialRates.brickUnit(brickType),
        },
        'steel': {'quantity': _round(totalSteel, 1), 'unit': 'kg'},
        'sand': {'quantity': _round(totalSand, 2), 'unit': 'm3'},
        'aggregate': {'quantity': _round(totalAggregate, 2), 'unit': 'm3'},
      },
      'specs': {'brickType': brickType},
      'steelByDiameter': steelSchedule,
      'assumptions': assumptions,
      'openingDeductions': {
        'doorCount': doorCount,
        'windowCount': windowCount,
        'openingArea': _round(openingArea, 2),
        'netWallArea': _round(netWallArea, 2),
      },
      'breakdown': {
        'brickMasonry': {
          'grossWallArea_m2': _round(wallArea, 2),
          'openingsDeducted_m2': _round(openingArea, 2),
          'netWallArea_m2': _round(netWallArea, 2),
          'bricks_nos': totalBricks.toInt(),
          'cement_bags': _round(cementMasonry, 1),
          'sand_m3': _round(sandMasonry, 2),
        },
        'rccSlab': {
          'floorArea_m2': _round(floorArea, 2),
          'concrete_m3': _round(concreteVol, 2),
          'cement_bags': _round(cementSlab, 1),
          'steel_kg': _round(steelSlab, 1),
          'sand_m3': _round(sandSlab, 2),
          'aggregate_m3': _round(aggregateSlab, 2),
        },
        'columns': {
          'count': columnCount,
          'volume_m3': _round(colVol, 2),
          'cement_bags': _round(cementCol, 1),
          'steel_kg': _round(steelCol, 1),
        },
        'beams': {
          'totalLength_m': _round(beamLength, 2),
          'volume_m3': _round(beamVol, 2),
          'cement_bags': _round(cementBeam, 1),
          'steel_kg': _round(steelBeam, 1),
        },
        'plastering': {
          'area_m2': _round(plasterArea, 2),
          'cement_bags': _round(cementPlaster, 1),
          'sand_m3': _round(sandPlaster, 2),
        },
        'staircase': {
          'area_m2': _round(stairArea, 2),
          'cement_bags': _round(cementStair, 1),
        },
        'flooring': {
          'area_m2': _round(floorArea, 2),
          'screedCement_bags': _round(cementScreed, 1),
        },
      },
      'zoneBreakdown': <String, dynamic>{},
    };
  }

  /// Trade-wise labour days from CPWD productivity norms.
  static Map<String, dynamic> calculateLabour(
      Map<String, dynamic> materials, Map<String, dynamic> geometry) {
    final mats = (materials['materials'] as Map?) ?? const {};
    final double totalBricks =
        ((mats['bricks'] as Map?)?['quantity'] as num?)?.toDouble() ?? 0;
    final double concreteVolume = _d(geometry, 'totalFloorArea') * 0.15 +
        _d(geometry, 'beamLength') * 0.135;
    final double steelKg =
        ((mats['steel'] as Map?)?['quantity'] as num?)?.toDouble() ?? 0;
    final double totalWallArea = _d(geometry, 'totalWallArea');

    return {
      'brick_masonry': {
        'labour_days': totalBricks != 0 ? (totalBricks / 400).round() : 0,
        'trade': 'Mason',
        'norm': '400 bricks/mason/day',
        'norm_source': 'CPWD',
      },
      'rcc_concrete': {
        'labour_days': concreteVolume != 0 ? (concreteVolume / 1.5).round() : 0,
        'trade': 'Labourer',
        'norm': '1.5 m³ concrete/labour/day',
        'norm_source': 'CPWD',
      },
      'steel_fixing': {
        'labour_days': steelKg != 0 ? (steelKg / 200).round() : 0,
        'trade': 'Steel fixer',
        'norm': '200 kg steel/fixer/day',
        'norm_source': 'CPWD',
      },
      'plastering': {
        'labour_days': totalWallArea != 0 ? (totalWallArea / 11).round() : 0,
        'trade': 'Plasterer',
        'norm': '11 m² wall/plasterer/day',
        'norm_source': 'CPWD',
      },
    };
  }

  /// Interior / finishing estimation: tiles, paint, putty, sanitary fixtures and
  /// electrical points. Area-driven where possible (so it works even when room
  /// counts aren't detected), with documented Indian-residential assumptions.
  /// Returns the same {materials, assumptions, breakdown} shape as structural so
  /// the UI renders it identically.
  static Map<String, dynamic> calculateInterior(Map<String, dynamic> geometry,
      {String floorTileSize = '600x600'}) {
    final assumptions = <String>[];
    final double floorArea = _d(geometry, 'totalFloorArea');
    final int floorCount = (geometry['floorCount'] is num)
        ? (geometry['floorCount'] as num).toInt()
        : 1;

    // Paintable wall area: use detected wall area/length, else the standard
    // ~3.2× carpet-area rule of thumb for residential interiors.
    double wallArea = _d(geometry, 'totalWallArea');
    if (wallArea == 0 && _d(geometry, 'totalWallLength') > 0) {
      wallArea = _d(geometry, 'totalWallLength') * _standardHeight;
    }
    if (wallArea == 0 && floorArea > 0) {
      wallArea = floorArea * 3.2;
      assumptions.add('Interior wall area derived from floor area × 3.2 '
          '(no wall geometry detected)');
    }

    // Room counts from the parser (may be sparse).
    final rc = (geometry['roomCounts'] as Map?) ?? const {};
    int rcOf(String k) => (rc[k] is num) ? (rc[k] as num).toInt() : 0;
    int bathrooms = rcOf('bathroom');
    int kitchens = rcOf('kitchen');
    final int detectedRooms = rc.values
        .fold<int>(0, (s, v) => s + ((v is num) ? v.toInt() : 0));
    if (bathrooms == 0 && floorArea > 0) {
      bathrooms = (floorArea / 45).ceil().clamp(1, 6);
      assumptions.add('Bathroom count estimated from floor area '
          '(none detected): $bathrooms');
    }
    if (kitchens == 0 && floorArea > 0) {
      kitchens = 1;
      assumptions.add('Kitchen count assumed: 1 (none detected)');
    }
    // Rooms used for electrical-point estimates.
    final int rooms =
        detectedRooms > 0 ? detectedRooms : (floorArea / 12).round().clamp(1, 40);

    // Perimeter for skirting.
    final double perimeter = _d(geometry, 'totalWallLength') > 0
        ? _d(geometry, 'totalWallLength')
        : (floorArea > 0 ? 4 * math.sqrt(floorArea) : 0);

    // ── Finishes ──────────────────────────────────────────────────────
    // Box coverage depends on the selected tile size (area is unchanged).
    final double tileBoxM2 = MaterialRates.tileM2PerBox(floorTileSize);
    final double floorTileArea = floorArea * 1.10; // 10% wastage
    final int floorTileBoxes = (floorTileArea / tileBoxM2).ceil();

    final double skirtingLen = perimeter; // running metres

    final double bathDado = bathrooms * 22.0; // walls up to ~2.1m
    final double kitchenDado = kitchens * 9.0; // counter band
    final double dadoArea = (bathDado + kitchenDado) * 1.10;
    final int dadoBoxes = (dadoArea / tileBoxM2).ceil();

    final double paintableArea = wallArea + floorArea; // walls + ceiling
    final double puttyBags = paintableArea / 28.0; // 2 coats, ~28 m²/40kg bag
    final double primerLitres = paintableArea / 10.0; // 1 coat
    final double paintLitres = paintableArea * 2 / 10.0; // 2 coats

    // ── Electrical points (estimated from area — room labels are too coarse
    // to count reliably; ~1 light/8m², 1 fan/22m², 1 socket/7m², 1 board/14m²).
    final int lightPoints = (floorArea / 8).round().clamp(1, 80);
    final int fanPoints = (floorArea / 22).round().clamp(1, 30);
    final int socketPoints = (floorArea / 7).round().clamp(1, 80);
    final int switchBoards = (floorArea / 14).round().clamp(1, 40);

    return {
      'materials': {
        'floor_tiles': {'quantity': _round(floorTileArea, 1), 'unit': 'm2'},
        'skirting': {'quantity': _round(skirtingLen, 1), 'unit': 'm'},
        'wall_dado_tiles': {'quantity': _round(dadoArea, 1), 'unit': 'm2'},
        'wall_putty': {'quantity': _round(puttyBags, 1), 'unit': 'bags'},
        'primer': {'quantity': _round(primerLitres, 1), 'unit': 'L'},
        'emulsion_paint': {'quantity': _round(paintLitres, 1), 'unit': 'L'},
        'wc': {'quantity': bathrooms, 'unit': 'nos'},
        'washbasin': {'quantity': bathrooms, 'unit': 'nos'},
        'shower_tap_set': {'quantity': bathrooms, 'unit': 'nos'},
        'kitchen_sink': {'quantity': kitchens, 'unit': 'nos'},
        'light_points': {'quantity': lightPoints, 'unit': 'nos'},
        'fan_points': {'quantity': fanPoints, 'unit': 'nos'},
        'socket_points': {'quantity': socketPoints, 'unit': 'nos'},
        'switch_boards': {'quantity': switchBoards, 'unit': 'nos'},
      },
      'specs': {'floorTileSize': floorTileSize},
      'assumptions': assumptions,
      'breakdown': {
        'flooring': {
          'tileSize': MaterialRates.tileLabel(floorTileSize),
          'tileArea_m2': _round(floorTileArea, 1),
          'boxes': floorTileBoxes,
          'skirting_m': _round(skirtingLen, 1),
        },
        'dado': {
          'tileSize': MaterialRates.tileLabel(floorTileSize),
          'bathroomArea_m2': _round(bathDado, 1),
          'kitchenArea_m2': _round(kitchenDado, 1),
          'boxes': dadoBoxes,
        },
        'painting': {
          'paintableArea_m2': _round(paintableArea, 1),
          'coats': 2,
          'putty_bags': _round(puttyBags, 1),
          'primer_L': _round(primerLitres, 1),
        },
        'fixtures': {'bathrooms': bathrooms, 'kitchens': kitchens},
        'electrical': {
          'rooms': rooms,
          'lightPoints': lightPoints,
          'fanPoints': fanPoints,
          'socketPoints': socketPoints,
          'switchBoards': switchBoards,
        },
        'floorCount': floorCount,
      },
    };
  }

  /// Split a total steel weight into a typical residential bar-diameter
  /// distribution (8–20mm). Used by the results screen where only the steel
  /// total is available (not the per-element split). Sums to [totalKg].
  static Map<String, double> typicalSteelSchedule(double totalKg) {
    const dist = {
      '8mm': 0.20,
      '10mm': 0.20,
      '12mm': 0.25,
      '16mm': 0.25,
      '20mm': 0.10,
    };
    return dist.map((k, v) => MapEntry(k, _round(totalKg * v, 1)));
  }

  /// Full /estimate response, computed locally.
  static Map<String, dynamic> estimate(
      String projectId, Map<String, dynamic> geometry,
      {String brickType = 'modular_mix'}) {
    final materials = calculateMaterials(geometry, brickType: brickType);
    final labour = calculateLabour(materials, geometry);
    final totalLabourDays = labour.values
        .fold<int>(0, (s, l) => s + ((l['labour_days'] as num?)?.toInt() ?? 0));
    return {
      'projectId': projectId,
      'materials': materials,
      'labour': labour,
      'total_labour_days': totalLabourDays,
      'confidence': 'high',
    };
  }
}
