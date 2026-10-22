import sys
from pathlib import Path
import fitz

# Ensure modules is in path
sys.path.append(str(Path(__file__).parent))

from modules.ml_pdf_parser import parse_pdf_ml
from modules.pdf_parser import parse_pdf_file as parse_pdf_legacy

test_files = [
    '../Finalized dxf and pdf files/2BHK 30x50 house.pdf',
    '../Pdf plans/00-6030-08 Costco 531 S Mississauga, ON - Washroom Remodel -Architectural (1).pdf',
    '../Pdf plans/building.pdf',
]

for filepath in test_files:
    try:
        doc = fitz.open(filepath)
        word_count = len(doc[0].get_text('words'))
        doc.close()
        
        if word_count > 10:
            result = parse_pdf_ml(filepath)
        else:
            result = parse_pdf_legacy(filepath)
            result['confidence'] = min(
                result.get('confidence', 0.4), 0.3)
            result['warning'] = 'Scanned PDF — legacy parser used'
        
        name = filepath.split('/')[-1][-40:]
        print(f"File: {name}")
        print(f"  Router: {'ML' if word_count > 10 else 'Legacy'}")
        print(f"  Area: {result.get('totalFloorArea',0):.2f}m²")
        print(f"  Walls: {result.get('totalWallLength',0):.2f}m")
        print(f"  Scale: {result.get('scaleUsed','N/A')}")
        print(f"  Confidence: {result.get('confidence',0):.2f}")
        print(f"  Rooms: {result.get('roomCounts',{})}")
        print()
    except Exception as e:
        print(f"Error on {filepath}: {e}")
        import traceback
        traceback.print_exc()
