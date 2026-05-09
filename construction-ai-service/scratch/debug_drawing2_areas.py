import sys
import os

sys.path.append(os.path.abspath('modules'))
from cad_parser import _strategy_1_closed_polylines
import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/Drawing2.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.0254

result = _strategy_1_closed_polylines(msp, scale)
print(f"Strategy 1 Result: {result}")

# Let's manually see the areas before deduplication
areas = []
for e in msp:
    if e.dxftype() == 'LWPOLYLINE' and e.is_closed:
        # Simplified Shoelace
        pts = e.get_points()
        a = 0.0
        for i in range(len(pts)):
            p1 = pts[i]
            p2 = pts[(i+1)%len(pts)]
            a += (p1[0]*p2[1]) - (p2[0]*p1[1])
        area = abs(a)/2.0 * (scale**2)
        if area > 5.0:
            areas.append({'area': area, 'layer': e.dxf.layer})

print(f"\nAll closed poly areas > 5m2:")
for i, ar in enumerate(areas):
    print(f"Shape {i}: {ar['area']:.2f} m2 on layer {ar['layer']}")
