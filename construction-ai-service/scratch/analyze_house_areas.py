import ezdxf
import math

def _shoelace(points):
    n = len(points)
    if n < 3: return 0.0
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += points[i][0] * points[j][1]
        area -= points[j][0] * points[i][1]
    return abs(area / 2.0)

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.001 # house.dxf is mm?

# house.dxf scale detection said mm (INSUNITS=4) in previous run
# Unit detection: millimetres (INSUNITS=4) (scale=0.001)

areas = []
for e in msp:
    if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
        if hasattr(e, 'get_points'):
            pts = [(p[0]*scale, p[1]*scale) for p in e.get_points()]
        else:
            pts = [(v.dxf.location[0]*scale, v.dxf.location[1]*scale) for v in e.vertices]
        if len(pts) >= 3:
            a = _shoelace(pts)
            if a > 1.0:
                print(f"Layer: {e.dxf.layer}, Area: {a:.2f}")
                areas.append(a)

print(f"Total Area found: {sum(areas):.2f}")
