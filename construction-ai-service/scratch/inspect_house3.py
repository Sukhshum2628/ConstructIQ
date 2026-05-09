import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house 3.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

print("--- Layer Check ---")
layers = set()
for e in msp:
    layers.add(e.dxf.layer)
print(f"Layers: {sorted(list(layers))}")

print("\n--- Entity Sample ---")
for i, e in enumerate(msp):
    if i < 20:
        print(f"Entity {i}: {e.dxftype()} on layer {e.dxf.layer}")
