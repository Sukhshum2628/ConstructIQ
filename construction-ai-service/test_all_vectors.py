from modules.pdf_parser import parse_pdf_file
from modules.estimation_engine import calculate_materials
import os

pdf_files = [
    "1BHK 15x30 house.pdf",
    "1BHK 24x22 house.pdf",
    "2BHK 30x50 house.pdf",
    "3BHK 20x45 house.pdf",
    "3BHK 40x50 house.pdf",
    "building.pdf",
    "home_floor_plan.pdf",
    "house_plan.pdf"
]

project_root = "c:/Users/sukhs/OneDrive/Documents/8th_Sem_Project"

print(f"{'Filename':<25} | {'Area (m2)':<10} | {'Wall (m)':<10} | {'Bricks':<10} | {'Cement (Bags)'}")
print("-" * 75)

for pdf in pdf_files:
    full_path = os.path.join(project_root, pdf)
    try:
        result = parse_pdf_file(full_path)
        if 'error' in result:
            print(f"{pdf:<25} | ERROR: {result['error']}")
            continue
            
        mats = calculate_materials(result)
        area = result.get('totalFloorArea', 0)
        wall = result.get('totalWallLength', 0)
        bricks = mats.get('materials', {}).get('bricks', {}).get('quantity', 0)
        cement = mats.get('materials', {}).get('cement', {}).get('quantity', 0)
        
        print(f"{pdf:<25} | {area:<10.2f} | {wall:<10.2f} | {bricks:<10} | {cement:<10.1f}")
    except Exception as e:
        print(f"{pdf:<25} | CRASH: {str(e)}")
