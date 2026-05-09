import ezdxf
import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)) + '/..')
from modules.cad_parser import _detect_and_confirm_scale, _find_overall_span

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house_plan.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale, _ = _detect_and_confirm_scale(doc, msp)

h_dims = []
v_dims = []
for e in msp:
    if e.dxftype() == 'DIMENSION':
        val = abs(e.dxf.actual_measurement) * scale
        if not (0.3 <= val <= 50.0): continue
        p1 = e.dxf.defpoint
        p2 = e.dxf.defpoint2
        dx = abs(p2[0] - p1[0])
        dy = abs(p2[1] - p1[1])
        if dx > dy * 2: h_dims.append((val, e.dxf.layer))
        elif dy > dx * 2: v_dims.append((val, e.dxf.layer))

print("Horizontal Dims:")
for v, l in sorted(h_dims, reverse=True):
    print(f"  {v:.2f} ({l})")

print("Vertical Dims:")
for v, l in sorted(v_dims, reverse=True):
    print(f"  {v:.2f} ({l})")
