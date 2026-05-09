import ezdxf
import math

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/Drawing2.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.0254

def get_poly_pts(e, scale):
    if hasattr(e, 'get_points'):
        return [(p[0]*scale, p[1]*scale) for p in e.get_points()]
    elif hasattr(e, 'vertices'):
        return [(v.dxf.location[0]*scale, v.dxf.location[1]*scale) for v in e.vertices]
    return []

def get_shoelace(pts):
    n = len(pts)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += pts[i][0] * pts[j][1]
        area -= pts[j][0] * pts[i][1]
    return abs(area / 2.0)

shapes = []
for e in msp:
    if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
        pts = get_poly_pts(e, scale)
        if len(pts) < 3: continue
        a = get_shoelace(pts)
        if 5.0 <= a <= 5000.0:
            mid_x = sum(p[0] for p in pts) / len(pts)
            mid_y = sum(p[1] for p in pts) / len(pts)
            shapes.append({'area': a, 'mid': (mid_x, mid_y)})

print(f"Detected {len(shapes)} shapes:")
for i, s in enumerate(shapes):
    print(f"Shape {i}: Area={s['area']:.2f}, Midpoint={s['mid']}")
