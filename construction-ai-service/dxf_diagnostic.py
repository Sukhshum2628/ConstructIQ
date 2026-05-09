"""
Diagnostic script to analyze DXF files and understand what data is available.
This helps identify why the parser is producing incorrect measurements.
"""
import ezdxf
import math
import re
import sys
from collections import defaultdict

def diagnose(filepath):
    doc = ezdxf.readfile(filepath)
    msp = doc.modelspace()
    
    print(f"\n{'='*80}")
    print(f"DIAGNOSTIC REPORT: {filepath}")
    print(f"{'='*80}")
    
    # 1. HEADER INFO
    insunits = doc.header.get('$INSUNITS', 0)
    unit_names = {0: 'Unspecified', 1: 'Inches', 2: 'Feet', 3: 'Miles', 
                  4: 'Millimeters', 5: 'Centimeters', 6: 'Meters', 
                  7: 'Kilometers', 8: 'Microinches', 9: 'Mils'}
    print(f"\n[1] HEADER — $INSUNITS = {insunits} ({unit_names.get(insunits, 'Unknown')})")
    
    # Also check DIMSCALE, LTSCALE, MEASUREMENT
    for var in ('$DIMSCALE', '$LTSCALE', '$MEASUREMENT', '$DIMLFAC', '$LUNITS'):
        try:
            val = doc.header.get(var, 'NOT SET')
            print(f"    {var} = {val}")
        except:
            pass
    
    # 2. ENTITY COUNT BY TYPE
    type_counts = defaultdict(int)
    for e in msp:
        type_counts[e.dxftype()] += 1
    print(f"\n[2] ENTITY COUNTS (total: {sum(type_counts.values())})")
    for etype, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        print(f"    {etype:20s}: {count}")
    
    # 3. LAYER BREAKDOWN
    layer_counts = defaultdict(lambda: defaultdict(int))
    for e in msp:
        layer_counts[e.dxf.layer][e.dxftype()] += 1
    
    print(f"\n[3] LAYER BREAKDOWN ({len(layer_counts)} layers)")
    for layer in sorted(layer_counts.keys()):
        total = sum(layer_counts[layer].values())
        types_str = ', '.join(f"{t}:{c}" for t, c in sorted(layer_counts[layer].items(), key=lambda x: -x[1])[:5])
        print(f"    {layer:30s}: {total:5d} entities  [{types_str}]")
    
    # 4. BOUNDING BOX
    all_x, all_y = [], []
    for e in msp:
        try:
            etype = e.dxftype()
            if etype == 'LINE':
                all_x += [e.dxf.start[0], e.dxf.end[0]]
                all_y += [e.dxf.start[1], e.dxf.end[1]]
            elif etype in ('LWPOLYLINE', 'POLYLINE'):
                if hasattr(e, 'get_points'):
                    for p in e.get_points():
                        all_x.append(p[0]); all_y.append(p[1])
                elif hasattr(e, 'vertices'):
                    for v in e.vertices:
                        all_x.append(v.dxf.location[0]); all_y.append(v.dxf.location[1])
        except:
            pass
    
    if all_x:
        bbox_w = max(all_x) - min(all_x)
        bbox_h = max(all_y) - min(all_y)
        print(f"\n[4] BOUNDING BOX (raw coords, no scaling)")
        print(f"    Width:  {bbox_w:.4f}")
        print(f"    Height: {bbox_h:.4f}")
        print(f"    Max dimension: {max(bbox_w, bbox_h):.4f}")
        
        # Interpretation
        bmax = max(bbox_w, bbox_h)
        print(f"\n    If units are mm:     {bmax*0.001:.2f} m × {min(bbox_w,bbox_h)*0.001:.2f} m")
        print(f"    If units are cm:     {bmax*0.01:.2f} m × {min(bbox_w,bbox_h)*0.01:.2f} m")
        print(f"    If units are inches: {bmax*0.0254:.2f} m × {min(bbox_w,bbox_h)*0.0254:.2f} m")
        print(f"    If units are feet:   {bmax*0.3048:.2f} m × {min(bbox_w,bbox_h)*0.3048:.2f} m")
        print(f"    If units are meters: {bmax:.2f} m × {min(bbox_w,bbox_h):.2f} m")
    
    # 5. DIMENSION ENTITIES (actual measurements embedded in drawing)
    dims = []
    dim_texts = []
    for e in msp:
        if e.dxftype() == 'DIMENSION':
            try:
                meas = e.dxf.actual_measurement
                dims.append(meas)
                text = getattr(e.dxf, 'text', '')
                dim_texts.append((meas, text, e.dxf.layer))
            except:
                pass
    
    print(f"\n[5] DIMENSION ENTITIES ({len(dims)} found)")
    if dims:
        print(f"    Min: {min(dims):.4f}   Max: {max(dims):.4f}   Avg: {sum(dims)/len(dims):.4f}")
        print(f"    Sample dimensions (first 30):")
        for meas, text, layer in dim_texts[:30]:
            print(f"      {meas:12.4f}  text='{text}'  layer={layer}")
        
        # Check which unit makes these plausible
        print(f"\n    Plausibility check (how many dims are 0.2m–20m in building range):")
        for scale, name in [(0.001, 'mm'), (0.01, 'cm'), (0.0254, 'in'), (0.3048, 'ft'), (1.0, 'm')]:
            hits = sum(1 for d in dims if 0.2 <= d*scale <= 20.0)
            pct = hits/len(dims)*100
            print(f"      {name:6s}: {hits}/{len(dims)} ({pct:.0f}%)")
    
    # 6. TEXT/MTEXT ANNOTATIONS (look for measurements)
    print(f"\n[6] TEXT ANNOTATIONS WITH MEASUREMENTS")
    area_pattern = re.compile(r'(\d+[\.,]?\d*)\s*(sq\.?\s*(?:m|ft|meter)|m²|ft²|sqm|sqft|m\s*sq|sq\s*m)', re.IGNORECASE)
    dim_pattern = re.compile(r"(\d+)\s*['\u2019]\s*-?\s*(\d+)\s*(?:\"|''|\u201D)?", re.IGNORECASE)  # feet-inches: 29'-10"
    metric_dim = re.compile(r'(\d+(?:\.\d+)?)\s*(?:x|×)\s*(\d+(?:\.\d+)?)\s*(m|mm|ft|feet)?', re.IGNORECASE)
    length_pattern = re.compile(r'(\d+(?:\.\d+)?)\s*(m|mm|cm|ft|feet|inches|in)\b', re.IGNORECASE)
    
    texts_found = []
    for e in msp:
        try:
            if e.dxftype() == 'TEXT':
                t = e.dxf.text.strip()
            elif e.dxftype() == 'MTEXT':
                t = e.text.strip()
            else:
                continue
            if t:
                texts_found.append((t, e.dxf.layer))
        except:
            continue
    
    print(f"  Total TEXT/MTEXT entities: {len(texts_found)}")
    
    # Search for area mentions
    area_mentions = []
    for t, layer in texts_found:
        m = area_pattern.search(t)
        if m:
            area_mentions.append((t, layer))
    
    if area_mentions:
        print(f"\n  AREA ANNOTATIONS FOUND ({len(area_mentions)}):")
        for t, layer in area_mentions[:20]:
            print(f"    [{layer}] \"{t}\"")
    
    # Search for feet-inches dimensions
    ft_in_mentions = []
    for t, layer in texts_found:
        m = dim_pattern.search(t)
        if m:
            ft_in_mentions.append((t, layer, m.group(0)))
    
    if ft_in_mentions:
        print(f"\n  FEET-INCHES ANNOTATIONS ({len(ft_in_mentions)}):")
        for t, layer, match in ft_in_mentions[:30]:
            print(f"    [{layer}] \"{t}\"  => matched: {match}")
    
    # Search for length mentions
    length_mentions = []
    for t, layer in texts_found:
        m = length_pattern.search(t)
        if m:
            length_mentions.append((t, layer))
    
    if length_mentions:
        print(f"\n  LENGTH ANNOTATIONS ({len(length_mentions)}):")
        for t, layer in length_mentions[:30]:
            print(f"    [{layer}] \"{t}\"")
    
    # All text dump (first 100 unique entries)
    print(f"\n  ALL TEXT CONTENT (first 100 unique):")
    seen = set()
    count = 0
    for t, layer in texts_found:
        key = t.strip().lower()
        if key not in seen and len(key) > 1:
            seen.add(key)
            count += 1
            if count <= 100:
                print(f"    [{layer:20s}] \"{t}\"")
    
    # 7. HATCH ENTITIES
    hatch_count = 0
    hatch_areas = []
    for e in msp:
        if e.dxftype() == 'HATCH':
            hatch_count += 1
            try:
                # Calculate area for each scale possibility
                for scale, name in [(0.001, 'mm'), (0.0254, 'in'), (0.3048, 'ft'), (1.0, 'm')]:
                    total = 0
                    for path in e.paths:
                        ptype = type(path).__name__
                        if 'PolylinePath' in ptype:
                            pts = [(v[0]*scale, v[1]*scale) for v in path.vertices]
                            n = len(pts)
                            area = 0
                            for i in range(n):
                                j = (i+1) % n
                                area += pts[i][0]*pts[j][1] - pts[j][0]*pts[i][1]
                            total += abs(area/2)
                    if total > 0.1:
                        hatch_areas.append((e.dxf.layer, name, total))
            except:
                pass
    
    print(f"\n[7] HATCH ENTITIES: {hatch_count}")
    if hatch_areas:
        print(f"  Sample hatch areas (first 30):")
        for layer, unit, area in hatch_areas[:30]:
            print(f"    [{layer:20s}] area={area:.2f} m² (assuming {unit})")
    
    # 8. BLOCK DEFINITIONS
    print(f"\n[8] BLOCK DEFINITIONS ({len(doc.blocks)} blocks)")
    for block in doc.blocks:
        if not block.name.startswith('*'):  # skip anonymous blocks
            entity_count = len(list(block))
            if entity_count > 0:
                print(f"    {block.name:30s}: {entity_count} entities")
    
    print(f"\n{'='*80}")
    print("END OF DIAGNOSTIC REPORT")
    print(f"{'='*80}\n")


if __name__ == '__main__':
    files = sys.argv[1:] or [
        r'C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\building.dxf',
        r'C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\house_plan.dxf',
    ]
    for f in files:
        try:
            diagnose(f)
        except Exception as ex:
            print(f"ERROR processing {f}: {ex}")
