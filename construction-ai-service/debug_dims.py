"""Debug script to see detailed dimension data for building.dxf"""
from modules.cad_parser import _detect_scale_factor, _extract_dimensions_info
import ezdxf

doc = ezdxf.readfile(r'C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\building.dxf')
msp = doc.modelspace()
scale, desc = _detect_scale_factor(doc, msp)
info = _extract_dimensions_info(msp, scale)

print(f"Scale: {scale} ({desc})")
print(f"\nAll dims sorted (m): {[round(d,2) for d in sorted(info['all_dims'], reverse=True)]}")
print(f"\nHorizontal dims (m): {[round(d,2) for d in sorted(info['horizontal_dims'], reverse=True)]}")
print(f"\nVertical dims (m): {[round(d,2) for d in sorted(info['vertical_dims'], reverse=True)]}")

# Calculate what the building bbox should be
# For a building with lots of room dimensions, we need to find the overall span
# The key insight: the LARGEST dimension chain (sum of consecutive dims) = building side
h_sorted = sorted(info['horizontal_dims'], reverse=True)
v_sorted = sorted(info['vertical_dims'], reverse=True)

print(f"\nTop 5 horizontal: {[round(d,2) for d in h_sorted[:5]]}, sum of top 5 = {sum(h_sorted[:5]):.1f}")
print(f"Top 5 vertical:   {[round(d,2) for d in v_sorted[:5]]}, sum of top 5 = {sum(v_sorted[:5]):.1f}")
print(f"Sum all h: {sum(h_sorted):.1f}m, Sum all v: {sum(v_sorted):.1f}m")
print(f"Sum all: {sum(info['all_dims']):.1f}m")

# Also check the bounding box of all non-excluded entities
all_x, all_y = [], []
for e in msp:
    try:
        layer = e.dxf.layer.lower()
        # Skip known non-plan layers
        if any(x in layer for x in ['elevation', 'section', 'front-', 'site']):
            continue
        etype = e.dxftype()
        if etype == 'LINE':
            all_x += [e.dxf.start[0] * scale, e.dxf.end[0] * scale]
            all_y += [e.dxf.start[1] * scale, e.dxf.end[1] * scale]
    except:
        pass

if all_x:
    w = max(all_x) - min(all_x)
    h = max(all_y) - min(all_y)
    print(f"\nFiltered bbox (excl elevation/section/site): {w:.1f}m x {h:.1f}m = {w*h:.0f} m²")

# Check building/details layer bbox specifically
for target_layer in ['BUILDING', 'DETAILS']:
    bx, by = [], []
    for e in msp:
        try:
            if e.dxf.layer.upper() != target_layer:
                continue
            etype = e.dxftype()
            if etype == 'LINE':
                bx += [e.dxf.start[0] * scale, e.dxf.end[0] * scale]
                by += [e.dxf.start[1] * scale, e.dxf.end[1] * scale]
            elif etype in ('LWPOLYLINE', 'POLYLINE'):
                if hasattr(e, 'get_points'):
                    for p in e.get_points():
                        bx.append(p[0] * scale)
                        by.append(p[1] * scale)
        except:
            pass
    if bx:
        w = max(bx) - min(bx)
        h = max(by) - min(by)
        print(f"{target_layer} layer bbox: {w:.1f}m x {h:.1f}m = {w*h:.0f} m²")
