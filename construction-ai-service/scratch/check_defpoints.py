import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/DEMO DRAWING.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

for e in msp:
    if e.dxftype() == 'DIMENSION':
        p1 = e.dxf.defpoint
        p2 = e.dxf.defpoint2
        p3 = e.dxf.defpoint3
        print(f"Dim {e.dxf.actual_measurement}: p1={p1}, p2={p2}, p3={p3}")
