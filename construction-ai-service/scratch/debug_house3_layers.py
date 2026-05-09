import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house 3.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

WALL_KW = {'wall', 'walls', 'partition', 'structure', 'structural', 'building'}
all_layer_names = [L.dxf.name.lower() for L in doc.layers]
print(f"All Layers: {all_layer_names}")

wall_layers_exist = any(any(kw in layer for kw in WALL_KW) for layer in all_layer_names)
print(f"Wall Layers Exist: {wall_layers_exist}")

# Filter loop simulation
count = 0
for e in msp:
    layer = e.dxf.layer.lower()
    is_wall_layer = any(kw in layer for kw in WALL_KW)
    is_permissive = not wall_layers_exist
    if not is_wall_layer and not is_permissive:
        pass
    else:
        count += 1
print(f"Entities that passed layer check: {count} out of {len(msp)}")
