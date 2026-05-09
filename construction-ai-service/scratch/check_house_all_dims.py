import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.001

for e in msp:
    if e.dxftype() == 'DIMENSION':
        m = abs(e.dxf.actual_measurement) * scale
        print(f"Dim: {m}")
