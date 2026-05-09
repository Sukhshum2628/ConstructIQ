import ezdxf
import os

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/building.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

layers = set()
for e in msp:
    layers.add(e.dxf.layer)

print("Layers in building.dxf:")
for l in sorted(layers):
    print(f"  {l}")

# Check what _strategy_0 finds
scale = 0.001
for e in msp:
    if e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
        if 'building' in e.dxf.layer.lower():
            print(f"Found polyline on layer {e.dxf.layer}")
