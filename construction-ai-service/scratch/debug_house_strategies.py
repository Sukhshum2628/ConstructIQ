import ezdxf
import sys
import os

# Ensure we can import from modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)) + '/..')

from modules.cad_parser import _strategy_3_dimensions, _detect_and_confirm_scale

path = 'C:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/house.dxf'
doc = ezdxf.readfile(path)
msp = doc.modelspace()

scale, scale_note = _detect_and_confirm_scale(doc, msp)
print(f"Scale: {scale} ({scale_note})")

res3 = _strategy_3_dimensions(msp, scale)
print(f"Strategy 3 Result: {res3}")

from modules.cad_parser import _strategy_0_outline_polylines, _strategy_1_closed_polylines, _strategy_2_hatch, _strategy_4_wall_bbox
res0 = _strategy_0_outline_polylines(msp, scale)
res1 = _strategy_1_closed_polylines(msp, scale)
res2 = _strategy_2_hatch(msp, scale)
res4 = _strategy_4_wall_bbox(msp, scale)

print(f"Strategy 0: {res0['area']} (conf {res0['confidence']})")
print(f"Strategy 1: {res1['area']} (conf {res1['confidence']})")
print(f"Strategy 2: {res2['area']} (conf {res2['confidence']})")
print(f"Strategy 4: {res4['area']} (conf {res4['confidence']})")
