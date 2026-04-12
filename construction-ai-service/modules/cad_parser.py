"""
Production-grade DXF parser for ConstructIQ.
Handles real architectural floor plans — walls, floors, columns,
doors, windows, beams, stairs, curves, and block references.
Outputs per-element breakdown for detailed material estimation.
"""
import math
import re
import ezdxf
import httpx
import tempfile
import os
from typing import Optional
from collections import defaultdict

WALL_PATTERNS   = ["wall", "walls", "a-wall", "arch-wall", "wl", "partition",
                   "cloison", "mur", "w-", "ext_wall", "int_wall", "bearing",
                   "exterior", "interior", "masonry"]
FLOOR_PATTERNS  = ["floor", "slab", "dalle", "a-flor", "flr", "ground",
                   "a-slab", "concrete", "rcc", "deck", "pavement", "paving"]
COLUMN_PATTERNS = ["column", "col", "pillar", "struct", "s-col", "a-col",
                   "support", "pier", "post", "rcc-col", "structure"]
DOOR_PATTERNS   = ["door", "a-door", "dr", "porte", "opening-door"]
WINDOW_PATTERNS = ["window", "win", "a-glaz", "fenetre", "glazing", "glass"]
BEAM_PATTERNS   = ["beam", "girder", "joist", "lintel", "a-beam", "rcc-beam"]
STAIR_PATTERNS  = ["stair", "step", "ramp", "escalier", "staircase"]
DIM_PATTERNS    = ["dim", "dimension", "anno", "annotation", "text", "a-anno"]


def _layer_matches(layer_name: str, patterns: list) -> bool:
    name = layer_name.lower().strip()
    return any(p in name for p in patterns)


def _shoelace_area(points: list) -> float:
    n = len(points)
    if n < 3:
        return 0.0
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += points[i][0] * points[j][1]
        area -= points[j][0] * points[i][1]
    return abs(area / 2.0)


def _arc_length(entity) -> float:
    try:
        radius = entity.dxf.radius
        start = math.radians(entity.dxf.start_angle)
        end = math.radians(entity.dxf.end_angle)
        if end < start:
            end += 2 * math.pi
        return radius * (end - start)
    except Exception:
        return 0.0


def _spline_length(entity) -> float:
    try:
        points = list(entity.flattening(0.01))
        total = 0.0
        for i in range(len(points) - 1):
            dx = points[i+1][0] - points[i][0]
            dy = points[i+1][1] - points[i][1]
            total += math.sqrt(dx*dx + dy*dy)
        return total
    except Exception:
        return 0.0


def _polyline_length_and_area(entity):
    try:
        pts = [(p[0], p[1]) for p in entity.get_points()]
        length = 0.0
        for i in range(len(pts) - 1):
            dx = pts[i+1][0] - pts[i][0]
            dy = pts[i+1][1] - pts[i][1]
            length += math.sqrt(dx*dx + dy*dy)
        if entity.is_closed and len(pts) > 1:
            dx = pts[0][0] - pts[-1][0]
            dy = pts[0][1] - pts[-1][1]
            length += math.sqrt(dx*dx + dy*dy)
        area = _shoelace_area(pts) if entity.is_closed else 0.0
        return length, area
    except Exception:
        return 0.0, 0.0


def _hatch_area(entity) -> float:
    try:
        total = 0.0
        for path in entity.paths:
            path_type = type(path).__name__
            if "PolylinePath" in path_type:
                pts = [(v[0], v[1]) for v in path.vertices]
                total += _shoelace_area(pts)
            elif "EdgePath" in path_type:
                pts = []
                for edge in path.edges:
                    etype = type(edge).__name__
                    if "LineEdge" in etype:
                        pts.append((edge.start[0], edge.start[1]))
                    elif "ArcEdge" in etype:
                        cx, cy = edge.center[0], edge.center[1]
                        r = edge.radius
                        sa = math.radians(edge.start_angle)
                        ea = math.radians(edge.end_angle)
                        if ea < sa:
                            ea += 2 * math.pi
                        for t in range(8):
                            angle = sa + (ea - sa) * t / 8
                            pts.append((cx + r*math.cos(angle),
                                        cy + r*math.sin(angle)))
                    elif "SplineEdge" in etype:
                        if hasattr(edge, 'control_points') and edge.control_points:
                            for cp in edge.control_points:
                                pts.append((cp[0], cp[1]))
                if pts:
                    total += _shoelace_area(pts)
        return total
    except Exception:
        return 0.0


def _extract_height(msp) -> tuple:
    """Extract building height from TEXT/MTEXT annotations."""
    height_pattern = re.compile(
        r'(\d+\.?\d*)\s*["\']?\s*(m|mm|ft|feet|meter|metre|\'|\")',
        re.IGNORECASE
    )
    candidates = []
    for entity in msp.query("TEXT MTEXT"):
        try:
            text = (entity.dxf.text
                    if hasattr(entity.dxf, 'text')
                    else entity.text)
            for val_str, unit in height_pattern.findall(text.strip()):
                val = float(val_str)
                if unit.lower() == 'mm':
                    val /= 1000
                elif unit.lower() in ('ft', 'feet', "'"):
                    val *= 0.3048
                if 2.0 <= val <= 20.0:
                    candidates.append(val)
        except Exception:
            continue
    if candidates:
        from collections import Counter
        best = Counter([round(v, 1) for v in candidates]).most_common(1)[0][0]
        return best, "extracted from drawing annotations"
    return None, "default 3.0m — no height annotation found in drawing"


def parse_dxf_file(file_path: str) -> dict:
    """Parse a DXF file and return comprehensive geometry breakdown."""
    doc = ezdxf.readfile(file_path)
    msp = doc.modelspace()

    wall_length_by_layer = defaultdict(float)
    floor_area_by_layer  = defaultdict(float)
    column_count = 0
    door_count   = 0
    window_count = 0
    beam_length  = 0.0
    stair_area   = 0.0
    hatch_found  = False

    def process(entity, override_layer=None):
        nonlocal column_count, door_count, window_count
        nonlocal beam_length, stair_area, hatch_found
        try:
            layer = override_layer or getattr(entity.dxf, 'layer', '0')
            etype = entity.dxftype()
            is_wall   = _layer_matches(layer, WALL_PATTERNS)
            is_floor  = _layer_matches(layer, FLOOR_PATTERNS)
            is_col    = _layer_matches(layer, COLUMN_PATTERNS)
            is_door   = _layer_matches(layer, DOOR_PATTERNS)
            is_win    = _layer_matches(layer, WINDOW_PATTERNS)
            is_beam   = _layer_matches(layer, BEAM_PATTERNS)
            is_stair  = _layer_matches(layer, STAIR_PATTERNS)

            if etype == "LINE":
                s, e = entity.dxf.start, entity.dxf.end
                ln = math.sqrt((e[0]-s[0])**2 + (e[1]-s[1])**2)
                if is_wall:  wall_length_by_layer[layer] += ln
                elif is_beam: beam_length += ln

            elif etype == "LWPOLYLINE":
                ln, area = _polyline_length_and_area(entity)
                if is_wall:  wall_length_by_layer[layer] += ln
                elif is_floor and area > 0.5: floor_area_by_layer[layer] += area
                elif is_stair and area > 0.5: stair_area += area
                elif is_beam: beam_length += ln
                elif area > 1.0 and not is_door and not is_win:
                    floor_area_by_layer['_untagged'] += area

            elif etype == "ARC":
                if is_wall: wall_length_by_layer[layer] += _arc_length(entity)

            elif etype == "SPLINE":
                if is_wall: wall_length_by_layer[layer] += _spline_length(entity)

            elif etype == "ELLIPSE":
                try:
                    ratio = abs(entity.dxf.ratio)
                    major = entity.dxf.major_axis
                    r_maj = math.sqrt(major[0]**2 + major[1]**2)
                    r_min = r_maj * ratio
                    h = ((r_maj - r_min)/(r_maj + r_min))**2
                    perim = math.pi*(r_maj+r_min)*(1+3*h/(10+math.sqrt(4-3*h)))
                    if is_wall: wall_length_by_layer[layer] += perim
                except Exception:
                    pass

            elif etype == "CIRCLE":
                if is_col:
                    column_count += 1
                elif is_floor:
                    floor_area_by_layer[layer] += math.pi * entity.dxf.radius**2

            elif etype == "HATCH":
                area = _hatch_area(entity)
                if area > 0.5:
                    if is_floor or is_stair:
                        floor_area_by_layer[layer] += area
                        hatch_found = True
                    elif not is_wall:
                        floor_area_by_layer['_hatch'] += area
                        hatch_found = True

            elif etype == "INSERT":
                if is_door: door_count += 1
                elif is_win: window_count += 1
                elif is_col: column_count += 1

        except Exception:
            pass

    for e in msp:
        process(e)

    # Expand block inserts for geometry inside blocks
    try:
        for ins in msp.query("INSERT"):
            bname = ins.dxf.name
            if bname in doc.blocks:
                for be in doc.blocks[bname]:
                    process(be, override_layer=ins.dxf.layer)
    except Exception:
        pass

    # Compute totals
    total_wall_length = sum(wall_length_by_layer.values())
    total_floor_area  = sum(v for v in floor_area_by_layer.values() if v > 0.5)
    height, h_source  = _extract_height(msp)
    h = height if height else 3.0

    total_wall_area   = total_wall_length * h
    structural_volume = total_floor_area  * h

    # Confidence scoring
    score = 0
    if total_wall_length > 0: score += 3
    if total_floor_area  > 0: score += 3
    if height is not None:    score += 2
    if column_count > 0:      score += 1
    if hatch_found:           score += 1
    confidence = "high" if score >= 8 else "medium" if score >= 5 else "low"

    return {
        "totalWallLength":   round(total_wall_length, 2),
        "totalWallArea":     round(total_wall_area, 2),
        "totalFloorArea":    round(total_floor_area, 2),
        "totalColumnCount":  column_count,
        "buildingHeight":    h,
        "heightSource":      h_source,
        "structuralVolume":  round(structural_volume, 2),
        "beamLength":        round(beam_length, 2),
        "stairArea":         round(stair_area, 2),
        "doorCount":         door_count,
        "windowCount":       window_count,
        "wallLengthByLayer": dict(wall_length_by_layer),
        "floorAreaByLayer":  {k: round(v, 2) for k, v in floor_area_by_layer.items() if v > 0.5},
        "confidence":        confidence,
        "confidenceScore":   score,
        "hatchAreasFound":   hatch_found,
        "entityCounts": {
            "walls": len(wall_length_by_layer),
            "floors": len(floor_area_by_layer),
            "columns": column_count,
            "doors": door_count,
            "windows": window_count,
        },
    }


async def parse_from_url(file_url: str) -> dict:
    """Download DXF from Firebase Storage URL and parse."""
    with tempfile.NamedTemporaryFile(suffix=".dxf", delete=False) as f:
        async with httpx.AsyncClient() as client:
            r = await client.get(file_url, timeout=60.0)
            r.raise_for_status()
            f.write(r.content)
            tmp = f.name
    try:
        return parse_dxf_file(tmp)
    finally:
        os.unlink(tmp)


def parse_from_bytes(file_bytes: bytes) -> dict:
    """Parse DXF from raw bytes — used by /parse-cad-upload endpoint."""
    with tempfile.NamedTemporaryFile(suffix=".dxf", delete=False) as f:
        f.write(file_bytes)
        tmp = f.name
    try:
        return parse_dxf_file(tmp)
    finally:
        os.unlink(tmp)
