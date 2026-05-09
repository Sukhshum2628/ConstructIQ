import ezdxf
import math

def _shoelace_area(points):
    n = len(points)
    if n < 3: return 0.0
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += points[i][0] * points[j][1]
        area -= points[j][0] * points[i][1]
    return abs(area / 2.0)

doc = ezdxf.readfile(r'C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\house_plan.dxf')
msp = doc.modelspace()
scale = 0.0254

print(f"{'Layer':<20} | {'Area (m2)':<10} | {'Closed'}")
print("-" * 40)

for e in msp:
    if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
        if hasattr(e, 'get_points'):
            pts = [(p[0] * scale, p[1] * scale) for p in e.get_points()]
        else:
            continue
            
        area = _shoelace_area(pts)
        is_closed = getattr(e, 'is_closed', False)
        
        # Nearly closed check
        dist = 0
        if len(pts) > 1:
            dist = math.sqrt((pts[0][0]-pts[-1][0])**2 + (pts[0][1]-pts[-1][1])**2)
        
        if area > 10:
            status = "Yes" if is_closed else (f"Near ({dist:.3f}m)" if dist < 0.2 else "No")
            print(f"{e.dxf.layer:<20} | {area:<10.1f} | {status}")
