from modules.cad_parser import parse_dxf_file
import os

files = [
    (r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\building.dxf", "BUILDING (Target 387m2)"),
    (r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\house_plan.dxf", "HOUSE_PLAN (Target 90m2)"),
    (r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\house.dxf", "NEW HOUSE FILE")
]

for file_path, label in files:
    print(f"\n{'='*60}\n  {label}\n{'='*60}")
    try:
        result = parse_dxf_file(file_path)
        print(f"  Floor Area: {result['totalFloorArea']:.1f} m²")
        print(f"  Wall Length: {result['totalWallLength']:.1f} m")
        print(f"  Source: {result['floorAreaSource']}")
        print(f"  Confidence: {result['confidence']} ({result['confidenceScore']}/10)")
        dim_info = result.get('dimensionInfo', {})
        print(f"  Spans: {dim_info.get('maxHorizontalSpan', 0):.1f}m x {dim_info.get('maxVerticalSpan', 0):.1f}m")
    except Exception as e:
        print(f"  Error parsing {label}: {e}")
