import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house_plan.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

layers = set()
for e in msp:
    layers.add(e.dxf.layer)

print("Layers in house_plan.dxf:")
for l in sorted(layers):
    print(f"  {l}")

scale = 0.0254 # inches
for e in msp:
    if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
        if 'outline' in e.dxf.layer.lower() or 'plan' in e.dxf.layer.lower() or 'building' in e.dxf.layer.lower():
            from modules.cad_parser import _get_polyline_pts, _shoelace
            pts = _get_polyline_pts(e, scale)
            if len(pts) >= 3:
                a = _shoelace(pts)
                print(f"Layer: {e.dxf.layer}, Area: {a:.2f}")
