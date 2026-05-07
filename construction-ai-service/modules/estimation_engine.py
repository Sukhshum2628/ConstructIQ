"""
Estimation engine for ConstructIQ.
Uses CPWD (Central Public Works Department) standard formulas for construction materials.
"""

def calculate_materials(geometry: dict) -> dict:
    """
    CPWD QTO formulas. Returns material quantities ONLY — no cost.
    """
    project_type = geometry.get("projectType", "new_build")
    
    # ── Normalisation & Assumptions ─────────────────────────────────
    # Standard values for Indian residential construction (CPWD standards)
    STANDARD_HEIGHT = 3.0  # metres
    SLAB_THICKNESS = 0.15  # metres
    
    geo = dict(geometry)  # Avoid mutating input
    assumptions = []

    # Derive wall area if missing
    if not geo.get('totalWallArea') and geo.get('totalWallLength'):
        geo['totalWallArea'] = geo['totalWallLength'] * STANDARD_HEIGHT
        assumptions.append(f'Wall area derived from wall length × {STANDARD_HEIGHT}m height')

    # Derive concrete volume if missing
    if not geo.get('concreteVolume') and geo.get('totalFloorArea'):
        # 0.15m is the standard residential slab thickness in India
        geo['concreteVolume'] = geo['totalFloorArea'] * SLAB_THICKNESS
        assumptions.append(f'Concrete volume derived from floor area × {SLAB_THICKNESS}m slab thickness')

    # Defaults for counts if missing
    if geo.get('doorCount') is None:
        geo['doorCount'] = 0
        assumptions.append('Door count not detected — no door deductions applied')
        
    if geo.get('windowCount') is None:
        geo['windowCount'] = 0
        assumptions.append('Window count not detected — no window deductions applied')

    if geo.get('floorCount') is None:
        geo['floorCount'] = 1

    # Use normalised values
    wall_area      = geo.get("totalWallArea", 0)
    floor_area     = geo.get("totalFloorArea", 0)

    if project_type == 'renovation':
        return {
            'projectType': 'renovation',
            'materials': {
                'wall_tiles':   {'quantity': round(wall_area, 1),  'unit': 'm2'},
                'floor_tiles':  {'quantity': round(floor_area, 1), 'unit': 'm2'},
                'paint':        {'quantity': round(wall_area, 1),  'unit': 'm2'},
            },
            'assumptions': assumptions,
            'note': (
                'Renovation project detected. Showing finish area quantities '
                'instead of structural materials (bricks, cement, steel). '
                'Structural quantities are not applicable for remodel work.'
            ),
            'openingDeductions': {},
            'breakdown': {},
            'zoneBreakdown': {}
        }

    struct_vol     = geo.get("structuralVolume", 0)
    beam_length    = geo.get("beamLength", 0)
    stair_area     = geo.get("stairArea", 0)
    column_count   = geo.get("totalColumnCount", 0)
    door_count     = geo.get("doorCount", 0)
    window_count   = geo.get("windowCount", 0)
    height         = geo.get("buildingHeight", STANDARD_HEIGHT)

    # ── Opening deductions ──────────────────────────────────────────
    # Standard opening sizes (CPWD norms):
    #   Door:   0.9m wide × 2.1m high = 1.89 m² per door
    #   Window: 1.2m wide × 1.2m high = 1.44 m² per window
    DOOR_AREA   = 0.9 * 2.1   
    WINDOW_AREA = 1.2 * 1.2   

    opening_area = (door_count * DOOR_AREA) + (window_count * WINDOW_AREA)
    net_wall_area = max(0.0, wall_area - opening_area)

    # Brick masonry (uses net area)
    total_bricks    = net_wall_area * 190
    cement_masonry  = net_wall_area * 0.85
    sand_masonry    = net_wall_area * 0.15

    # RCC Structure (Slab + Foundation + Beams + Columns)
    # Use normalised concreteVolume if present
    concrete_vol    = geo.get("concreteVolume", floor_area * 0.45) 
    cement_slab     = concrete_vol * 8.2    
    sand_slab       = concrete_vol * 0.45
    aggregate_slab  = concrete_vol * 0.85
    steel_slab      = concrete_vol * 75.0   

    # Beams/Columns/Plaster as before...
    stair_vol       = stair_area * 0.20
    cement_stair    = stair_vol * 8
    aggregate_stair = stair_vol * 0.84

    beam_vol        = beam_length * 0.069   
    cement_beam     = beam_vol * 8
    aggregate_beam  = beam_vol * 0.84
    steel_beam      = beam_vol * 7850 * 0.02

    col_vol         = column_count * 0.053 * height
    cement_col      = col_vol * 8
    aggregate_col   = col_vol * 0.84
    steel_col       = col_vol * 7850 * 0.03

    plaster_area    = wall_area * 1.8
    cement_plaster  = plaster_area * 0.11
    sand_plaster    = plaster_area * 0.022

    cement_screed   = floor_area * 0.044
    sand_screed     = floor_area * 0.008

    # Totals
    total_cement    = (cement_masonry + cement_slab + cement_stair +
                       cement_beam + cement_col + cement_plaster + cement_screed)
    total_sand      = sand_masonry + sand_slab + sand_plaster + sand_screed
    total_aggregate = aggregate_slab + aggregate_stair + aggregate_beam + aggregate_col
    total_steel     = steel_slab + steel_beam + steel_col

    return {
        "materials": {
            "cement":    {"quantity": round(total_cement, 1),    "unit": "bags"},
            "bricks":    {"quantity": int(total_bricks),          "unit": "nos"},
            "steel":     {"quantity": round(total_steel, 1),      "unit": "kg"},
            "sand":      {"quantity": round(total_sand, 2),       "unit": "m3"},
            "aggregate": {"quantity": round(total_aggregate, 2),  "unit": "m3"},
        },
        "assumptions": assumptions,
        "openingDeductions": {
            "doorCount": door_count,
            "windowCount": window_count,
            "openingArea": round(opening_area, 2),
            "netWallArea": round(net_wall_area, 2),
        },
        "breakdown": {
            "brickMasonry": {
                "grossWallArea_m2":   round(wall_area, 2),
                "openingsDeducted_m2": round(opening_area, 2),
                "netWallArea_m2":     round(net_wall_area, 2),
                "bricks_nos":         int(total_bricks),
                "cement_bags":        round(cement_masonry, 1),
                "sand_m3":            round(sand_masonry, 2),
            },
            "rccSlab": {
                "floorArea_m2":   round(floor_area, 2),
                "concrete_m3":    round(concrete_vol, 2),
                "cement_bags":    round(cement_slab, 1),
                "steel_kg":       round(steel_slab, 1),
                "sand_m3":        round(sand_slab, 2),
                "aggregate_m3":   round(aggregate_slab, 2),
            },
            "columns": {
                "count":        column_count,
                "volume_m3":    round(col_vol, 2),
                "cement_bags":  round(cement_col, 1),
                "steel_kg":     round(steel_col, 1),
            },
            "beams": {
                "totalLength_m": round(beam_length, 2),
                "volume_m3":     round(beam_vol, 2),
                "cement_bags":   round(cement_beam, 1),
                "steel_kg":      round(steel_beam, 1),
            },
            "plastering": {
                "area_m2":      round(plaster_area, 2),
                "cement_bags":  round(cement_plaster, 1),
                "sand_m3":      round(sand_plaster, 2),
            },
            "staircase": {
                "area_m2":     round(stair_area, 2),
                "cement_bags": round(cement_stair, 1),
            },
            "flooring": {
                "area_m2":          round(floor_area, 2),
                "screedCement_bags": round(cement_screed, 1),
            },
        },
        "zoneBreakdown": {},  
    }


def calculate_labour(materials: dict, geometry: dict) -> dict:
    """Calculates trade-wise labour days based on CPWD productivity norms."""
    total_bricks    = materials.get("bricks", {}).get("quantity", 0)
    concrete_volume = (geometry.get("totalFloorArea", 0.0) * 0.15 + 
                       geometry.get("beamLength", 0.0) * 0.135)
    steel_kg        = materials.get("steel", {}).get("quantity", 0.0)
    total_wall_area = geometry.get("totalWallArea", 0.0)

    return {
        "brick_masonry": {
            "labour_days": round(total_bricks / 400) if total_bricks else 0,
            "trade": "Mason",
            "norm": "400 bricks/mason/day",
            "norm_source": "CPWD"
        },
        "rcc_concrete": {
            "labour_days": round(concrete_volume / 1.5) if concrete_volume else 0,
            "trade": "Labourer",
            "norm": "1.5 m³ concrete/labour/day",
            "norm_source": "CPWD"
        },
        "steel_fixing": {
            "labour_days": round(steel_kg / 200) if steel_kg else 0,
            "trade": "Steel fixer",
            "norm": "200 kg steel/fixer/day",
            "norm_source": "CPWD"
        },
        "plastering": {
            "labour_days": round(total_wall_area / 11) if total_wall_area else 0,
            "trade": "Plasterer",
            "norm": "11 m² wall/plasterer/day",
            "norm_source": "CPWD"
        }
    }
