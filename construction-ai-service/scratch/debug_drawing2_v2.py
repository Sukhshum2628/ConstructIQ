import sys
import os
import math

sys.path.append(os.path.abspath('modules'))
from cad_parser import _is_closed, _get_polyline_pts, _shoelace
import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/Drawing2.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.0254

print(f"--- Strategy 1 Logic Simulation ---")
areas = []
for e in msp:
    if e.dxftype() not in ('LWPOLYLINE', 'POLYLINE'):
        continue
    pts = _get_polyline_pts(e, scale)
    if len(pts) < 3: continue
    if not _is_closed(e, pts, tol=0.15): continue
    a = _shoelace(pts)
    if 2.0 <= a <= 5000.0:
        areas.append({'area': a, 'layer': e.dxf.layer, 'type': e.dxftype()})

print(f"Detected {len(areas)} areas:")
for i, ar in enumerate(areas):
    print(f"Shape {i}: {ar['area']:.2f} m2 on layer {ar['layer']} ({ar['type']})")

from cad_parser import _deduplicate_areas
deduped = _deduplicate_areas([a['area'] for a in areas])
print(f"\nDeduped Areas: {deduped}")
print(f"Total: {sum(deduped):.2f} m2")
