import os
import re
import math
import fitz
import ezdxf
import tempfile
import numpy as np
from typing import Dict, Any, List, Tuple
from collections import defaultdict

import modules.cad_parser as cad_parser

def parse_pdf_file(filepath: str) -> Dict[str, Any]:
    doc = fitz.open(filepath)
    page = doc[0]
    page_rect = page.rect
    
    # 1. Extraction
    drawings = page.get_drawings()
    raw_lines = []
    for d in drawings:
        for item in d["items"]:
            if item[0] == "l":
                raw_lines.append(((item[1].x, item[1].y), (item[2].x, item[2].y)))
            elif item[0] == "re":
                r = item[1]
                p1, p2, p3, p4 = (r.x0, r.y0), (r.x1, r.y0), (r.x1, r.y1), (r.x0, r.y1)
                raw_lines.extend([(p1, p2), (p2, p3), (p3, p4), (p4, p1)])

    if not raw_lines:
        return {'error': 'NO_GEOMETRY', 'message': 'No vector lines found in PDF'}

    # 2. Scale Calibration (Consensus with Mode Bias)
    words = page.get_text("words")
    page_width = max(page_rect.width, page_rect.height)
    default_scale = 0.045 if page_width < 1500 else 0.08 
    
    scale_multiplier = default_scale
    scale_source = f"Fallback ({default_scale})"
    confidence_score = 0.4
    
    scale_samples = []
    for w in words:
        val_m = _parse_dimension_to_meters(w[4])
        if val_m and val_m > 0:
            mx, my = (w[0] + w[2]) / 2, (w[1] + w[3]) / 2
            candidates = []
            for p1, p2 in raw_lines:
                dist = math.dist((mx, my), ((p1[0]+p2[0])/2, (p1[1]+p2[1])/2))
                if dist < 30:
                    line_len = math.dist(p1, p2)
                    if line_len > 10: candidates.append(line_len)
            if candidates:
                scale_samples.append(val_m / max(candidates))

    if scale_samples:
        plausible = [s for s in scale_samples if 0.01 < s < 0.15]
        if plausible:
            hist, bin_edges = np.histogram(plausible, bins=12)
            best_bin = np.argmax(hist)
            in_bin = [s for s in plausible if bin_edges[best_bin] <= s <= bin_edges[best_bin+1]]
            scale_multiplier = float(np.median(in_bin))
            scale_source = f"OCR Calibrated Scale (from {len(plausible)} dims)"
            confidence_score = 0.9

    # 3. Geometric Isolation (Union-Find)
    n = len(raw_lines)
    parent = list(range(n))
    def find(i):
        root = i
        while parent[root] != root: root = parent[root]
        while parent[i] != root:
            new_p = parent[i]; parent[i] = root; i = new_p
        return root
    def union(i, j):
        root_i, root_j = find(i), find(j)
        if root_i != root_j: parent[root_i] = root_j

    pt_map = defaultdict(list)
    for i, (p1, p2) in enumerate(raw_lines):
        if math.dist(p1, p2) > page_width * 0.45: continue 
        for p in (p1, p2):
            key = (round(p[0]/2)*2, round(p[1]/2)*2)
            pt_map[key].append(i)
    for indices in pt_map.values():
        for i in range(len(indices)-1): union(indices[i], indices[i+1])

    clusters = defaultdict(list)
    for i in range(n): clusters[find(i)].append(i)
    
    # 4. Aggregation with Floor Similarity Filter
    all_islands = []
    for root, indices in clusters.items():
        island_len_pts = sum(math.dist(raw_lines[i][0], raw_lines[i][1]) for i in indices)
        if island_len_pts < 300: continue
        
        xs = [raw_lines[i][0][0] for i in indices] + [raw_lines[i][1][0] for i in indices]
        ys = [raw_lines[i][0][1] for i in indices] + [raw_lines[i][1][1] for i in indices]
        w_pts, h_pts = max(xs)-min(xs), max(ys)-min(ys)
        
        # Density check
        perimeter_pts = 2 * (w_pts + h_pts)
        if perimeter_pts > 0 and (island_len_pts / perimeter_pts) < 1.8: continue
            
        area_m2 = w_pts * h_pts * scale_multiplier**2 
        if 10.0 < area_m2 < 3000.0:
            all_islands.append({'area': area_m2, 'len': island_len_pts})

    if not all_islands:
        return {'error': 'NO_FLOOR_FOUND', 'message': 'No architectural plans identified'}

    # SIMILARITY FILTER: Identify the primary floor and only sum islands of comparable size
    # This keeps Ground/First/Second floors but drops small sheds/labels/auxiliary geometry
    max_island_area = max(i['area'] for i in all_islands)
    # Threshold: Include any island at least 40% as large as the primary floor
    significant_islands = [i for i in all_islands if i['area'] > max_island_area * 0.4]
    
    total_area = sum(i['area'] for i in significant_islands)
    total_wall_len = sum(i['len'] for i in significant_islands) * scale_multiplier
    floor_count = len(significant_islands)

    return {
        'totalFloorArea': round(total_area, 2),
        'totalWallLength': round(total_wall_len, 2),
        'floorCount': floor_count,
        'areaSource': f'Similarity-Filtered Extraction ({floor_count} floors)',
        'scaleSource': scale_source,
        'confidence': confidence_score,
        'unitDetected': 'metres'
    }

def _parse_dimension_to_meters(text: str) -> float:
    text = text.strip()
    fi = re.match(r"^(\d+)['\u2019]?(?:-?(\d+)[\"\u201d]?)?$", text)
    if fi: return (float(fi.group(1))*12 + (float(fi.group(2)) if fi.group(2) else 0))*0.0254
    nums = re.findall(r"\d+\.?\d*", text.lower())
    if not nums: return 0.0
    val = float(nums[0])
    if 'mm' in text.lower(): return val/1000.0
    if 'm' in text.lower() and 'mm' not in text.lower(): return val
    return val/1000.0 if val > 100 else val
