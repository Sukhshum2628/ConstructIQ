import ezdxf
import math

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/Drawing2.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

def get_poly_area(p):
    # Simplified area for comparison
    pts = p.get_points()
    if not pts: return 0
    area = 0.0
    for i in range(len(pts)):
        p1 = pts[i]
        p2 = pts[(i + 1) % len(pts)]
        area += (p1[0] * p2[1]) - (p2[0] * p1[1])
    return abs(area) / 2.0

shapes = []
for e in msp:
    if e.dxftype() == 'LWPOLYLINE' and e.is_closed:
        a = get_poly_area(e)
        if a > 10000: # Significant area
            mid_x = sum(p[0] for p in e.get_points()) / len(e.get_points())
            mid_y = sum(p[1] for p in e.get_points()) / len(e.get_points())
            shapes.append({'area': a, 'mid': (mid_x, mid_y)})

print(f"Found {len(shapes)} large closed shapes:")
for i, s in enumerate(shapes):
    print(f"Shape {i}: Area={s['area']:.1f}, Midpoint={s['mid']}")
