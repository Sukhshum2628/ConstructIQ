import ezdxf
import os

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

layers = set()
for e in msp:
    layers.add(e.dxf.layer)

print("Layers in house.dxf:")
for l in sorted(layers):
    print(f"  {l}")
