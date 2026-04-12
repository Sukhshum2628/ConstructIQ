"""
Estimation engine for ConstructIQ.
Uses CPWD (Central Public Works Department) standard formulas for construction materials.
"""

def calculate_materials(geometry: dict) -> dict:
    """
    CPWD QTO formulas. Returns material quantities ONLY — no cost.
    """
    wall_area      = geometry.get("totalWallArea", 0)
    floor_area     = geometry.get("totalFloorArea", 0)
    struct_vol     = geometry.get("structuralVolume", 0)
    beam_length    = geometry.get("beamLength", 0)
    stair_area     = geometry.get("stairArea", 0)
    column_count   = geometry.get("totalColumnCount", 0)
    door_count     = geometry.get("doorCount", 0)
    window_count   = geometry.get("windowCount", 0)
    height         = geometry.get("buildingHeight", 3.0)

    # Deduct openings from wall area (avg door=2.1m², window=1.2m²)
    opening_area  = (door_count * 2.1) + (window_count * 1.2)
    net_wall_area = max(0.0, wall_area - opening_area)

    # Brick masonry
    total_bricks    = net_wall_area * 50
    cement_masonry  = net_wall_area * 0.3
    sand_masonry    = net_wall_area * 0.06

    # RCC slab
    concrete_vol    = floor_area * 0.15
    cement_slab     = concrete_vol * 8
    sand_slab       = concrete_vol * 0.42
    aggregate_slab  = concrete_vol * 0.84
    steel_slab      = struct_vol  * 78.5

    # Staircase (slightly thicker slab)
    stair_vol       = stair_area * 0.20
    cement_stair    = stair_vol * 8
    aggregate_stair = stair_vol * 0.84

    # Beams
    beam_vol        = beam_length * 0.069   # 230×300mm section
    cement_beam     = beam_vol * 8
    aggregate_beam  = beam_vol * 0.84
    steel_beam      = beam_vol * 7850 * 0.02

    # Columns
    col_vol         = column_count * 0.053 * height
    cement_col      = col_vol * 8
    aggregate_col   = col_vol * 0.84
    steel_col       = col_vol * 7850 * 0.03

    # Plastering (1.8× net wall area for both faces)
    plaster_area    = net_wall_area * 1.8
    cement_plaster  = plaster_area * 0.11
    sand_plaster    = plaster_area * 0.022

    # Flooring screed
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
        "zoneBreakdown": {},  # populated if layer data available
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
