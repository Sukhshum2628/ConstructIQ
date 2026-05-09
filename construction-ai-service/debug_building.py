"""Check BUILDING layer entities — are they plan outlines?"""
import ezdxf, math

doc = ezdxf.readfile(r'C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\building.dxf')
msp = doc.modelspace()

# Check BUILDING layer entities
print("BUILDING layer entities:")
for e in msp:
    if e.dxf.layer != 'BUILDING':
        continue
    etype = e.dxftype()
    if etype == 'LINE':
        s, en = e.dxf.start, e.dxf.end
        ln = math.sqrt((en[0]-s[0])**2 + (en[1]-s[1])**2) * 0.001
        print(f"  LINE: ({s[0]:.0f},{s[1]:.0f}) -> ({en[0]:.0f},{en[1]:.0f})  length={ln:.2f}m")
    elif etype == 'LWPOLYLINE':
        pts = list(e.get_points())
        lens = []
        for i in range(len(pts)-1):
            dx = pts[i+1][0] - pts[i][0]
            dy = pts[i+1][1] - pts[i][1]
            lens.append(math.sqrt(dx*dx+dy*dy)*0.001)
        total_l = sum(lens)
        print(f"  LWPOLYLINE: {len(pts)} pts, total_len={total_l:.2f}m, closed={e.is_closed}")
        for p in pts:
            print(f"    ({p[0]:.0f}, {p[1]:.0f})")

# Check HATCH layer (plan floor hatches?)
print(f"\nHATCH layer entities: {sum(1 for e in msp if e.dxf.layer == 'HATCH')}")
for e in msp:
    if e.dxf.layer == 'HATCH' and e.dxftype() == 'HATCH':
        total_area = 0
        for path in e.paths:
            ptype = type(path).__name__
            if 'PolylinePath' in ptype:
                pts = [(v[0]*0.001, v[1]*0.001) for v in path.vertices]
                n = len(pts)
                area = 0
                for i in range(n):
                    j = (i+1)%n
                    area += pts[i][0]*pts[j][1] - pts[j][0]*pts[i][1]
                total_area += abs(area/2)
        if total_area > 0.1:
            print(f"  HATCH area = {total_area:.2f} m2")

# Check DETAILS layer - what's the plan view bbox?  
# Plan view entities are typically clustered in one area
print("\nDETAILS layer entity Y ranges:")
details_ys = {}
for e in msp:
    if e.dxf.layer != 'DETAILS':
        continue
    try:
        if e.dxftype() == 'LINE':
            y_avg = (e.dxf.start[1] + e.dxf.end[1]) / 2
        else:
            continue
        # bucket by Y (to find clusters = different views)
        bucket = round(y_avg / 5000) * 5000  # 5m buckets
        if bucket not in details_ys:
            details_ys[bucket] = 0
        details_ys[bucket] += 1
    except:
        pass
print("  Y-buckets (entities per 5m band):")
for y in sorted(details_ys.keys()):
    print(f"    Y={y*0.001:.0f}m: {details_ys[y]} entities")
