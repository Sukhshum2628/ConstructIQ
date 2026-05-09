import sys
import os
import json

# Add modules directory to path
sys.path.append(os.path.abspath('modules'))

from cad_parser import parse_dxf_file
from estimation_engine import calculate_materials

def test_all():
    files = [
        '../building.dxf',
        '../house.dxf',
        '../house_plan.dxf',
        '../DEMO DRAWING.dxf',
        '../house 3.dxf',
        '../Drawing2.dxf'
    ]
    
    print(f"{'File':<25} | {'Area (m2)':<10} | {'Wall (m)':<10} | {'Floors':<6} | {'Cement':<10} | {'Bricks':<10}")
    print("-" * 85)
    
    for f in files:
        try:
            cad_data = parse_dxf_file(f)
            if 'error' in cad_data:
                print(f"{os.path.basename(f):<25} | ERROR: {cad_data['message']}")
                continue
                
            est = calculate_materials(cad_data)
            mats = est.get('materials', {})
            
            area = cad_data.get('totalFloorArea', 0)
            wall = cad_data.get('totalWallLength', 0)
            floors = cad_data.get('floorCount', 1)
            cement = mats.get('cement', {}).get('quantity', 0)
            bricks = mats.get('bricks', {}).get('quantity', 0)
            
            print(f"{os.path.basename(f):<25} | {area:<10} | {wall:<10} | {floors:<6} | {cement:<10} | {bricks:<10}")
            
        except Exception as e:
            print(f"{os.path.basename(f):<25} | EXCEPTION: {str(e)}")

if __name__ == "__main__":
    test_all()
