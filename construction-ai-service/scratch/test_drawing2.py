import sys
import os
import json

# Add modules directory to path
sys.path.append(os.path.abspath('modules'))

from cad_parser import parse_dxf_file
from estimation_engine import calculate_materials

def test_drawing2():
    dxf_path = '../Drawing2.dxf'
    print(f"--- Parsing: {dxf_path} ---")
    
    try:
        # 1. Parse CAD data
        cad_data = parse_dxf_file(dxf_path)
        print(json.dumps(cad_data, indent=2))
        
        if 'error' in cad_data:
            print(f"Error: {cad_data['message']}")
            return

        # 2. Run Estimation
        print("\n--- Running Estimation ---")
        results = calculate_materials(cad_data)
        
        print(f"Project Type: {cad_data.get('buildingType', 'residential')}")
        print(f"Efficiency: {cad_data.get('efficiency', 1.0)}")
        print("\nEstimates:")
        
        materials = results.get('materials', {})
        for key, val in materials.items():
            print(f"  {key}: {val.get('quantity')} {val.get('unit')}")
                
    except Exception as e:
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_drawing2()
