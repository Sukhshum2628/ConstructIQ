import os

FILE_PATH = r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\construction-ai-service\modules\cad_parser.py"

with open(FILE_PATH, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add new imports
if "import networkx as nx" not in content:
    content = content.replace("import math\n", "import math\nimport networkx as nx\nfrom sklearn.cluster import DBSCAN\nimport json\nimport numpy as np\n")

# 2. Extract lines up to parse_dxf_file
split_marker = "def parse_dxf_file(file_path: str) -> dict:"
parts = content.split(split_marker)

if len(parts) == 2:
    header_content = parts[0]
    rest_content = parts[1]
    
    # We also need to keep the file intake functions at the bottom
    intake_marker = "# ── FILE INTAKE ──"
    tail_parts = rest_content.split(intake_marker)
    tail_content = intake_marker + tail_parts[1] if len(tail_parts) > 1 else ""

    new_helpers = """
# ── NEW GEOMETRY ENGINE HELPERS ──────────────────────────────────────────────

def _detect_dominant_cluster(entities, scale: float) -> list:
    '''Isolate the main building geometry using DBSCAN clustering.'''
    points = []
    entity_refs = []
    
    for e in entities:
        etype = e.dxftype()
        if etype == 'LINE':
            points.append(((e.dxf.start[0] + e.dxf.end[0])/2 * scale, (e.dxf.start[1] + e.dxf.end[1])/2 * scale))
            entity_refs.append(e)
        elif etype in ('LWPOLYLINE', 'POLYLINE'):
            pts = e.get_points() if hasattr(e, 'get_points') else [v.dxf.location for v in getattr(e, 'vertices', [])]
            if pts:
                xs = [p[0]*scale for p in pts]
                ys = [p[1]*scale for p in pts]
                points.append((sum(xs)/len(xs), sum(ys)/len(ys)))
                entity_refs.append(e)
                
    if not points:
        return entities
        
    # Cluster points (eps=5m means elements within 5m belong to the same cluster)
    clustering = DBSCAN(eps=5.0, min_samples=2).fit(points)
    
    cluster_scores = defaultdict(int)
    cluster_entities = defaultdict(list)
    
    for i, label in enumerate(clustering.labels_):
        if label == -1: # Noise
            continue
        e = entity_refs[i]
        cluster_entities[label].append(e)
        # Score cluster (simplified: just count entities, can be enhanced with wall lengths)
        cluster_scores[label] += 1
        
    if not cluster_scores:
        return entities
        
    dominant_label = max(cluster_scores.items(), key=lambda x: x[1])[0]
    return cluster_entities[dominant_label]

def _build_wall_graph(entities, scale: float) -> float:
    '''Build planar graph from wall lines and detect cycles (rooms). Returns total area.'''
    G = nx.Graph()
    
    def snap(pt):
        # Snap to 50mm grid
        return (round(pt[0]/0.05)*0.05, round(pt[1]/0.05)*0.05)
        
    for e in entities:
        if e.dxftype() == 'LINE':
            p1 = snap((e.dxf.start[0]*scale, e.dxf.start[1]*scale))
            p2 = snap((e.dxf.end[0]*scale, e.dxf.end[1]*scale))
            if p1 != p2:
                G.add_edge(p1, p2, length=math.dist(p1, p2))
                
    try:
        cycles = nx.cycle_basis(G)
        total_area = 0.0
        loop_areas = []
        for cycle in cycles:
            if len(cycle) >= 3:
                area = _shoelace_area(cycle)
                loop_areas.append(area)
        
        if not loop_areas:
            return 0.0
            
        # The largest loop is usually the outer boundary
        max_loop = max(loop_areas)
        inner_loops = sum(loop_areas) - max_loop
        
        # If inner loops roughly match outer loop, use inner loops (sum of rooms)
        # Otherwise, trust the largest loop as the footprint
        if inner_loops > max_loop * 0.5:
            return inner_loops
        return max_loop
    except Exception:
        return 0.0

def _load_patterns():
    try:
        with open('parser_patterns.json', 'r') as f:
            return json.load(f)
    except Exception:
        return []

def _validate_sanity(area, alt_areas):
    '''Reject area if it drastically disagrees with highly confident alternatives.'''
    valid_alts = [a for a in alt_areas if a > 0]
    if not valid_alts:
        return True
    avg_alt = sum(valid_alts) / len(valid_alts)
    if area < 0.5 * avg_alt or area > 2.0 * avg_alt:
        return False
    return True

# ── STRATEGIES ───────────────────────────────────────────────────────────────

def strategy_outline(outline_areas):
    total = sum(outline_areas) if outline_areas else 0.0
    return {"area": total, "confidence": 0.95 if total > 10.0 else 0.0, "source": "outline polylines"}

def strategy_dimension(dim_info, floor_count):
    area = dim_info['footprint_area'] * floor_count
    # High confidence if we have both horizontal and vertical dimensions
    conf = 0.85 if area > 10.0 and dim_info['max_horizontal_span'] > 0 and dim_info['max_vertical_span'] > 0 else 0.0
    return {"area": area, "confidence": conf, "source": "dimension footprint"}

def strategy_wall_loops(entities, scale, floor_count):
    area = _build_wall_graph(entities, scale) * floor_count
    return {"area": area, "confidence": 0.80 if area > 10.0 else 0.0, "source": "wall loop reconstruction"}

def strategy_text(text_areas):
    area = text_areas['total_annotated_area']
    return {"area": area, "confidence": 0.90 if area > 10.0 else 0.0, "source": text_areas['source']}

"""

    new_parse_dxf_file = """def parse_dxf_file(file_path: str) -> dict:
    '''
    Parse a DXF file and return comprehensive geometry breakdown.
    All returned measurements are in metres and square metres.
    '''
    doc = ezdxf.readfile(file_path)
    msp = doc.modelspace()

    # CHECK 1: Detect PDF-converted files before doing any geometry work
    is_pdf, pdf_reason = _detect_pdf_conversion(doc, msp)
    if is_pdf:
        return {
            'error': 'PDF_CONVERTED_DXF',
            'message': pdf_reason,
            'isPlausible': False,
            'confidence': 'rejected',
            'validation': {
                'isPlausible': False,
                'confidence': 'rejected',
                'warning': pdf_reason,
                'suggestedAction': 'Upload original DXF.',
                'llmUsed': False,
            },
            'totalWallLength': 0, 'totalFloorArea': 0, 'totalWallArea': 0,
            'totalColumnCount': 0, 'buildingHeight': 0, 'concreteVolume': 0,
            'unitDetected': 'unknown', 'scaleApplied': 0,
        }

    # Unit Detection
    scale, scale_description = _detect_scale_factor(doc, msp)
    print(f'Unit detection: {scale_description} (scale={scale})')

    wall_length_by_layer = defaultdict(float)
    floor_area_by_layer  = defaultdict(float)
    outline_areas        = []
    column_count = 0
    door_count   = 0
    window_count = 0
    beam_length  = 0.0
    stair_area   = 0.0
    hatch_found  = False
    
    # 1. Isolate Dominant Cluster
    all_entities = list(msp)
    dominant_entities = _detect_dominant_cluster(all_entities, scale)
    wall_entities = []

    def process_entity(entity, override_layer=None):
        nonlocal column_count, door_count, window_count
        nonlocal beam_length, stair_area, hatch_found

        try:
            layer = override_layer or getattr(entity.dxf, 'layer', '0')
            etype = entity.dxftype()

            if _is_excluded(layer):
                return

            is_wall   = _layer_matches(layer, WALL_RULES)
            is_floor  = _layer_matches(layer, FLOOR_RULES)
            is_col    = _layer_matches(layer, COLUMN_RULES)
            is_door   = _layer_matches(layer, DOOR_RULES)
            is_win    = _layer_matches(layer, WINDOW_RULES)
            is_beam   = _layer_matches(layer, BEAM_RULES)
            is_stair  = _layer_matches(layer, STAIR_RULES)
            is_outline = _layer_matches(layer, OUTLINE_RULES)

            if is_wall:
                wall_entities.append(entity)

            if etype == 'LINE':
                s, e = entity.dxf.start, entity.dxf.end
                ln = math.sqrt((e[0] - s[0]) ** 2 + (e[1] - s[1]) ** 2) * scale
                if not (0.05 <= ln <= 500): return
                if is_wall:
                    wall_length_by_layer[layer] += ln
                elif is_beam:
                    beam_length += ln

            elif etype in ('LWPOLYLINE', 'POLYLINE'):
                ln, area = _polyline_length_and_area(entity, scale)
                if is_outline and area > 5.0:
                    outline_areas.append(area)
                    wall_length_by_layer[layer] += ln
                elif is_wall:
                    wall_length_by_layer[layer] += ln
                    if area > 10.0:
                        outline_areas.append(area)
                elif is_floor and 1.0 <= area <= 5000:
                    floor_area_by_layer[layer] += area
                    hatch_found = True

            elif etype == 'CIRCLE':
                if is_col: column_count += 1
                elif is_floor: floor_area_by_layer[layer] += math.pi * (entity.dxf.radius * scale)**2
                
            elif etype == 'INSERT':
                if is_door: door_count += 1
                elif is_win: window_count += 1
                elif is_col: column_count += 1

        except Exception:
            pass

    for e in dominant_entities:
        process_entity(e)

    try:
        for ins in msp.query('INSERT'):
            bname = ins.dxf.name
            if bname in doc.blocks:
                for be in doc.blocks[bname]:
                    process_entity(be, override_layer=ins.dxf.layer)
    except Exception:
        pass

    dim_info = _extract_dimensions_info(dominant_entities, scale)
    text_areas = _extract_area_from_text(dominant_entities, scale)
    
    floor_count, floor_source = _detect_floor_count(msp)
    if outline_areas:
        floor_count = len(outline_areas)
        floor_source = f"{floor_count} outlines found"

    # --- NEW: CONFIDENCE-BASED STRATEGY ENGINE ---
    strategies = [
        strategy_text(text_areas),
        strategy_outline(outline_areas),
        strategy_dimension(dim_info, floor_count),
        strategy_wall_loops(wall_entities, scale, floor_count)
    ]
    
    valid_strategies = [s for s in strategies if s['area'] > 0 and s['confidence'] > 0]
    
    if valid_strategies:
        best_strategy = max(valid_strategies, key=lambda x: x['confidence'])
        total_floor_area_all_floors = best_strategy['area']
        floor_area_source = best_strategy['source']
        confidence = 'high' if best_strategy['confidence'] >= 0.8 else 'medium'
    else:
        # Fallback
        total_floor_area_all_floors = sum(floor_area_by_layer.values()) * floor_count
        floor_area_source = 'fallback layer sum'
        confidence = 'low'

    total_wall_length_geo = sum(wall_length_by_layer.values())
    total_wall_length_all_floors = total_wall_length_geo * (floor_count if not outline_areas else 1)
    
    # Accurate Opening Deduction (Simplified projection via dimension)
    opening_deduction = (door_count * DOOR_WIDTH_DEFAULT) + (window_count * WINDOW_WIDTH_DEFAULT)
    if total_wall_length_all_floors > opening_deduction:
        total_wall_length_all_floors -= opening_deduction

    height, h_source = _extract_height(msp)
    h = height if height else 3.0

    building_type, efficiency_factor = _detect_building_type(msp)
    project_type, type_signals = _detect_project_type(msp)
    
    concrete_volume_all_floors  = total_floor_area_all_floors * 0.15
    total_wall_area_all_floors   = total_wall_length_all_floors * h
    
    floor_area_per_level = total_floor_area_all_floors / floor_count if floor_count > 0 else 0

    return {
        'unitDetected':       scale_description,
        'scaleApplied':       scale,
        'totalWallLength':    round(total_wall_length_all_floors, 2),
        'totalWallArea':      round(total_wall_area_all_floors, 2),
        'totalFloorArea':     round(total_floor_area_all_floors, 2),
        'floorAreaSource':    floor_area_source,
        'floorCount':         floor_count,
        'floorCountSource':   floor_source,
        'floorAreaPerLevel':  round(floor_area_per_level, 2),
        'concreteVolume':     round(concrete_volume_all_floors, 2),
        'totalColumnCount':   column_count,
        'buildingHeight':     h,
        'heightSource':       h_source,
        'structuralVolume':   round(total_floor_area_all_floors * h, 2),
        'beamLength':         round(beam_length, 2),
        'stairArea':          round(stair_area, 2),
        'doorCount':          door_count,
        'windowCount':        window_count,
        'projectType':        project_type,
        'projectTypeSignals': type_signals,
        'buildingType':       building_type,
        'efficiencyFactor':   efficiency_factor,
        'wallLengthByLayer':  {k: round(v, 2) for k, v in wall_length_by_layer.items()},
        'floorAreaByLayer':   {k: round(v, 2) for k, v in floor_area_by_layer.items() if v > 0.5},
        'wallLengthSource':   'geometry',
        'dimensionInfo': {
            'count':                 dim_info['dim_count'],
            'totalDimensionedLength': dim_info['total_dimensioned_length'],
            'maxHorizontalSpan':     dim_info['max_horizontal_span'],
            'maxVerticalSpan':       dim_info['max_vertical_span'],
            'dimensionFootprint':    dim_info['footprint_area'],
        },
        'textAreaInfo': {
            'totalAnnotatedArea':    text_areas['total_annotated_area'],
            'source':                text_areas['source'],
        },
        'confidence':         confidence,
        'confidenceScore':    10 if confidence == 'high' else 5,
        'hatchAreasFound':    hatch_found,
        'entityCounts': {
            'walls':   len(wall_length_by_layer),
            'floors':  len(floor_area_by_layer),
            'columns': column_count,
            'doors':   door_count,
            'windows': window_count,
            'heuristic_walls': False,
        },
    }
\n"""

    final_content = header_content + new_helpers + new_parse_dxf_file + tail_content
    
    with open(FILE_PATH, "w", encoding="utf-8") as f:
        f.write(final_content)
    print("Refactor successfully applied.")
else:
    print("Error: Could not find parse_dxf_file split marker.")
