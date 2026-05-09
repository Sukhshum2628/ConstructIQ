import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/DEMO DRAWING.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.0254 # inches to meters

print("--- Dimension Check ---")
for e in msp:
    if e.dxftype() == 'DIMENSION':
        m = abs(e.dxf.actual_measurement) * scale
        print(f"Dim: {m} (Layer: {e.dxf.layer})")
