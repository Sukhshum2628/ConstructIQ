import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/DEMO DRAWING.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

print("--- Hatch Check ---")
hatches = [e for e in msp if e.dxftype() == 'HATCH']
for i, h in enumerate(hatches):
    try:
        # ezdxf hatch area calculation
        # Note: hatch.area can be None if not computed
        print(f"Hatch {i} Layer: {h.dxf.layer}, Area: {h.dxf.area if hasattr(h.dxf, 'area') else 'N/A'}")
    except: pass

print("\n--- Polyline Check ---")
polys = [e for e in msp if e.dxftype() in ('LWPOLYLINE', 'POLYLINE')]
for i, p in enumerate(polys):
    if p.is_closed:
        print(f"Closed Poly {i} Layer: {p.dxf.layer}")

print("\n--- Layer Check ---")
layers = set()
for e in msp:
    layers.add(e.dxf.layer)
print(f"Layers: {sorted(list(layers))}")
