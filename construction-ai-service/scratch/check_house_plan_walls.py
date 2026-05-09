import ezdxf

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house_plan.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

wall_entities = 0
for e in msp:
    if 'wall' in e.dxf.layer.lower():
        wall_entities += 1

print(f"Wall entities in house_plan.dxf: {wall_entities}")

# Check for patterns
for e in msp:
    if 'wall' in e.dxf.layer.lower():
        if e.dxftype() == 'LINE':
            L = math.dist(e.dxf.start[:2], e.dxf.end[:2])
            if L < 0.1: # Very short lines?
                 pass
