import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()
scale = 0.001

for e in msp:
    if e.dxftype() == 'DIMENSION':
        m = e.dxf.actual_measurement
        # If actual_measurement is 0 or negative, it means it's not explicitly set
        # and we should check the text or compute it.
        # But usually ezdxf returns 0 if not set.
        print(f"Dimension actual_measurement: {m}, layer: {e.dxf.layer}")
