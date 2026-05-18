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

def _extract_dominant_color_lines(drawings) -> list:
    """
    Group all line segments by stroke color.
    If one color accounts for >70% of total line length,
    return only lines of that dominant color.
    Otherwise return all lines (fallback for single-color files).
    
    In AutoCAD PDF exports, each layer becomes a distinct color.
    The wall layer is almost always the dominant color by total length.
    """
    from collections import defaultdict
    import math
    
    color_lines = defaultdict(list)
    color_lengths = defaultdict(float)
    
    for d in drawings:
        color = d.get('color')
        if color is None:
            color_key = 'none'
        else:
            color_key = tuple(round(c, 2) for c in color)
        
        for item in d['items']:
            if item[0] == 'l':
                p1 = (item[1].x, item[1].y)
                p2 = (item[2].x, item[2].y)
                seg_len = math.dist(p1, p2)
                color_lines[color_key].append((p1, p2))
                color_lengths[color_key] += seg_len
            elif item[0] == 're':
                r = item[1]
                pts = [(r.x0,r.y0),(r.x1,r.y0),(r.x1,r.y1),(r.x0,r.y1)]
                for i in range(4):
                    p1, p2 = pts[i], pts[(i+1)%4]
                    seg_len = math.dist(p1, p2)
                    color_lines[color_key].append((p1, p2))
                    color_lengths[color_key] += seg_len
    
    if not color_lengths:
        return []
    
    total_length = sum(color_lengths.values())
    if total_length == 0:
        return []
    
    # Find dominant color
    dominant_color = max(color_lengths, key=color_lengths.get)
    dominant_pct = color_lengths[dominant_color] / total_length
    
    num_colors = len([c for c in color_lengths 
                      if color_lengths[c] > total_length * 0.01])
    
    all_lines = []
    for lines in color_lines.values():
        all_lines.extend(lines)
    
    # Only filter if there are multiple meaningful colors
    # AND one color clearly dominates
    # Hybrid Threshold Strategy:
    # 1. If >70% dominant, isolate layer + recover proximity neighbors (user fix)
    # 2. If 45-70% dominant, keep all layers (integrity) but ALLOW dedup
    # 3. If <45% dominant, keep all layers but DISABLE dedup (safety)
    if num_colors >= 3 and dominant_pct >= 0.70:
        dominant_lines = color_lines[dominant_color]
        other_lines = []
        for c, l_list in color_lines.items():
            if c != dominant_color:
                other_lines.extend(l_list)
        
        recovered = _recover_proximity_lines(dominant_lines, other_lines)
        return dominant_lines + recovered, True
    elif num_colors >= 3 and dominant_pct >= 0.45:
        return all_lines, True
    else:
        return all_lines, False

def _recover_proximity_lines(dom_lines, other_lines):
    """Keep other_lines if they are within 20pt perp distance of a dom_line with >30% overlap."""
    import math, bisect
    if not dom_lines or not other_lines: return []
    
    # Sort dom_lines by min_x for spatial lookup
    dom_keys = [min(l[0][0], l[1][0]) for l in dom_lines]
    sorted_idx = sorted(range(len(dom_lines)), key=lambda i: dom_keys[i])
    dom_sorted = [dom_lines[i] for i in sorted_idx]
    dom_starts = [dom_keys[i] for i in sorted_idx]
    
    recovered = []
    for p1, p2 in other_lines:
        min_x_o, max_x_o = min(p1[0], p2[0]), max(p1[0], p2[0])
        idx_start = bisect.bisect_left(dom_starts, min_x_o - 25)
        
        found = False
        for i in range(idx_start, len(dom_sorted)):
            d_line = dom_sorted[i]
            if dom_starts[i] > max_x_o + 25: break
            
            # Fast midpoint proximity check
            m1 = ((p1[0] + p2[0])/2, (p1[1] + p2[1])/2)
            m2 = ((d_line[0][0] + d_line[1][0])/2, (d_line[0][1] + d_line[1][1])/2)
            if abs(m1[0]-m2[0]) <= 20 and abs(m1[1]-m2[1]) <= 20:
                # Overlap check
                x_ov = max(0, min(max_x_o, max(d_line[0][0], d_line[1][0])) - max(min_x_o, dom_starts[i]))
                y_ov = max(0, min(max(p1[1], p2[1]), max(d_line[0][1], d_line[1][1])) - max(min(p1[1], p2[1]), min(d_line[0][1], d_line[1][1])))
                if max(x_ov, y_ov) > 0.3 * math.dist(p1, p2):
                    found = True
                    break
        if found: recovered.append((p1, p2))
    return recovered

def _identify_redundant_parallel_walls(lines: list, scale: float) -> list:
    """
    Architectural walls have two faces (inner/outer).
    This function returns a list of booleans indicating if a line
    is a redundant parallel face. We keep them for topology (area)
    but exclude them from wall length.
    """
    import math
    if scale < 0.01 or not lines:
        return [False] * len(lines)
    
    # Scale-adaptive thresholds to protect building details while catching residential walls
    if scale < 0.03:
        # Residential mode: Aggressive to catch thin partition faces
        MIN_WALL_THICK_M = 0.005 # Catch everything
        MAX_WALL_THICK_M = 1.2   # Catch massive columns
        MIN_OVERLAP = 0.01       # Catch 1% overlap
    else:
        # Building mode: Conservative to avoid pairing architectural details
        MIN_WALL_THICK_M = 0.08 
        MAX_WALL_THICK_M = 0.35
        MIN_OVERLAP = 0.4
        
    min_dist_px = MIN_WALL_THICK_M / scale
    max_dist_px = MAX_WALL_THICK_M / scale
    
    def line_angle(p1, p2):
        return math.atan2(p2[1]-p1[1], p2[0]-p1[0]) % math.pi
    
    def get_line_params(p1, p2, p3, p4):
        """
        Calculate perpendicular distance and longitudinal overlap.
        Projects p3 and p4 onto the infinite line of p1-p2.
        """
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        mag2 = dx*dx + dy*dy
        if mag2 == 0: return 999, 0
        
        # Project p3 and p4
        u3 = ((p3[0] - p1[0]) * dx + (p3[1] - p1[1]) * dy) / mag2
        u4 = ((p4[0] - p1[0]) * dx + (p4[1] - p1[1]) * dy) / mag2
        
        # Perpendicular distance (from p3 to line 1-2)
        p3_proj_x = p1[0] + u3 * dx
        p3_proj_y = p1[1] + u3 * dy
        perp_dist = math.dist(p3, (p3_proj_x, p3_proj_y))
        
        # Overlap check
        # Range of line 1-2 is [0, 1]
        # Range of line 3-4 projection is [min(u3,u4), max(u3,u4)]
        overlap_min = max(0, min(u3, u4))
        overlap_max = min(1, max(u3, u4))
        overlap_len = max(0, overlap_max - overlap_min)
        
        return perp_dist, overlap_len

    redundant = [False] * len(lines)
    
    def dedup_pass(lines_to_proc, sort_key_idx):
        # sort_key_idx: 0 for X, 1 for Y
        lines_sorted = sorted(lines_to_proc, key=lambda x: min(x[1][0][sort_key_idx], x[1][1][sort_key_idx]))
        redundant_in_pass = [False] * len(lines_sorted)
        
        for idx, (orig_idx, (p1, p2)) in enumerate(lines_sorted):
            if redundant[orig_idx]: continue
            
            len_i = math.dist(p1, p2)
            if len_i < 2: continue
            
            max_coord_i = max(p1[sort_key_idx], p2[sort_key_idx])
            angle_i = line_angle(p1, p2)
            
            for idx_j in range(idx + 1, len(lines_sorted)):
                j_orig_idx, (p3, p4) = lines_sorted[idx_j]
                if redundant[j_orig_idx]: continue
                
                # Tight window (max_dist_px * 1.5) since we have 2 passes for both axes
                if lines_sorted[idx_j][1][0][sort_key_idx] - max_coord_i > (max_dist_px * 1.5):
                    break
                    
                len_j = math.dist(p3, p4)
                if len_j < 2 or (min(len_i, len_j) / max(len_i, len_j) < 0.50):
                    continue
                    
                angle_j = line_angle(p3, p4)
                angle_diff = abs(angle_i - angle_j) % math.pi
                if angle_diff > math.pi/2: angle_diff = math.pi - angle_diff
                
                angle_tol = math.radians(20) if scale < 0.03 else math.radians(5)
                if angle_diff > angle_tol: continue
                
                perp_dist, overlap_ratio = get_line_params(p1, p2, p3, p4)
                if min_dist_px <= perp_dist <= max_dist_px and overlap_ratio > MIN_OVERLAP:
                    redundant[j_orig_idx] = True
                    # Do not break, one line i could mark multiple lines j as redundant

    # Pass 1: X-sorted
    dedup_pass(list(enumerate(lines)), 0)
    # Pass 2: Y-sorted
    dedup_pass(list(enumerate(lines)), 1)
    
    return redundant

def parse_pdf_file(filepath: str) -> Dict[str, Any]:
    doc = fitz.open(filepath)
    page = doc[0]
    page_rect = page.rect
    
    # 1. Extraction
    drawings = page.get_drawings()
    
    # Step 1: Extract lines grouped by color
    # Returns (lines, is_dominant_layer_isolated)
    raw_lines, dominant_layer_found = _extract_dominant_color_lines(drawings)
    
    # Extract wall geometry from filled paths
    # These appear in files printed via Microsoft Print to PDF
    # where thick walls become solid filled rectangles
    fill_lines = []
    for d in drawings:
        fill_color = d.get('fill')
        # Only process dark fills (walls are black or dark grey)
        if fill_color is None:
            continue
        # Check if fill is dark (all channels < 0.3)
        if isinstance(fill_color, (list, tuple)):
            if any(c > 0.3 for c in fill_color[:3]):
                continue  # skip light fills (rooms, backgrounds)
        elif fill_color != 0:
            continue
        
        # Get bounding rect of this filled path
        rect = d.get('rect')
        if rect is None:
            continue
        
        x0, y0, x1, y1 = rect.x0, rect.y0, rect.x1, rect.y1
        width = x1 - x0
        height = y1 - y0
        
        # A wall fill is elongated (aspect ratio > 3)
        # not a small square (which would be a door symbol)
        aspect = max(width, height) / max(min(width, height), 0.01)
        if aspect < 1.0:
            continue  # skip square fills (columns, door symbols)
        if max(width, height) < 1.5:
            continue  # skip tiny fills (noise)
        
        # Add the long axis as a wall line
        if width > height:
            fill_lines.append(((x0, (y0+y1)/2), (x1, (y0+y1)/2)))
        else:
            fill_lines.append((((x0+x1)/2, y0), ((x0+x1)/2, y1)))
    
    # Add fill-derived lines to raw_lines
    raw_lines.extend(fill_lines)
    
    # Step 1.1: Title Block Exclusion (bottom 10% and right 10%)
    page_rect = page.rect
    raw_lines = [
        (p1, p2) for p1, p2 in raw_lines
        if not (p1[1] > page_rect.height * 0.90 and p2[1] > page_rect.height * 0.90)
        and not (p1[0] > page_rect.width * 0.90 and p2[0] > page_rect.width * 0.90)
    ]
    
    if not raw_lines:
        return {'error': 'NO_GEOMETRY', 
                'message': 'No vector lines found in PDF'}

    # 2. Scale Calibration (Consensus with Mode Bias)
    words = page.get_text("words")
    page_width = max(page_rect.width, page_rect.height)
    
    # Calculate bounding box of geometry to detect if it's a full page
    all_coords = [p for line in raw_lines for p in line]
    geom_span = max(max(c[0] for c in all_coords)-min(c[0] for c in all_coords),
                    max(c[1] for c in all_coords)-min(c[1] for c in all_coords))
    
    # For A4/A3 pages with geometry spanning most of the page,
    # use a scale derived from standard architectural drawing sizes
    if page_width < 700:  # A4 portrait or landscape
        if geom_span > 400:  # geometry spans most of page
            default_scale = 0.035  # 1:100 scale assumption
        else:
            default_scale = 0.045  # keep existing fallback
    elif page_width < 1500: # A3 and similar
        default_scale = 0.045 # Keep existing fallback
    else:  # larger sheets
        default_scale = 0.08
    
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

    # Step 2: Mark redundant parallel wall pairs (inner faces)
    # ONLY if we isolated a dominant layer (walls are likely clean)
    if scale_multiplier > 0.01 and dominant_layer_found:
        redundant_mask = _identify_redundant_parallel_walls(
            raw_lines, scale_multiplier
        )
    else:
        redundant_mask = [False] * len(raw_lines)

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
    # Threshold for a line to be considered a "wall" line (prevents hatch noise)
    # Most structural walls are > 2m (approx 50-60 pts at standard scales)
    WALL_MIN_LEN_PTS = 55.0 

    for root, indices in clusters.items():
        # Total length of ALL lines in cluster (used for island identification)
        island_len_pts = sum(math.dist(raw_lines[i][0], raw_lines[i][1]) for i in indices)
        if island_len_pts < 300: continue
        
        xs = [raw_lines[i][0][0] for i in indices] + [raw_lines[i][1][0] for i in indices]
        ys = [raw_lines[i][0][1] for i in indices] + [raw_lines[i][1][1] for i in indices]
        w_pts, h_pts = max(xs)-min(xs), max(ys)-min(ys)
        
        # Density check: ensures it's a plan and not a sparse annotation
        perimeter_pts = 2 * (w_pts + h_pts)
        if perimeter_pts > 0 and (island_len_pts / perimeter_pts) < 1.8: continue
            
        area_m2 = w_pts * h_pts * scale_multiplier**2 
        if 10.0 < area_m2 < 3000.0:
            # Wall length calculation: only count lines above the noise threshold
            # and only if NOT marked as a redundant parallel wall face.
            wall_len_pts = sum(math.dist(raw_lines[i][0], raw_lines[i][1]) 
                              for i in indices 
                              if math.dist(raw_lines[i][0], raw_lines[i][1]) > WALL_MIN_LEN_PTS
                              and not redundant_mask[i])
            all_islands.append({'area': area_m2, 'len': wall_len_pts})

    if not all_islands:
        return {'error': 'NO_FLOOR_FOUND', 'message': 'No architectural plans identified'}

    # SIMILARITY FILTER: Identify the primary floor and only sum islands of comparable size
    max_island_area = max(i['area'] for i in all_islands)
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
