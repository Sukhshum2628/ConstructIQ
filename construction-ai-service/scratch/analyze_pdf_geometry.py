import fitz
import sys
import math

def analyze_pdf(filepath):
    doc = fitz.open(filepath)
    page = doc[0]
    drawings = page.get_drawings()
    print(f"File: {filepath}")
    print(f"Total Drawings: {len(drawings)}")
    
    for i, d in enumerate(drawings):
        is_closed = d.get("closed", False) or d.get("fill") is not None
        if not is_closed: continue
        
        vertices = []
        for item in d["items"]:
            if item[0] == "l":
                vertices.extend([item[1], item[2]])
            elif item[0] == "re":
                r = item[1]
                vertices.extend([fitz.Point(r.x0, r.y0), fitz.Point(r.x1, r.y0), 
                                 fitz.Point(r.x1, r.y1), fitz.Point(r.x0, r.y1)])
        
        if len(vertices) >= 3:
            # Shoelace in points
            area = 0.0
            for j in range(len(vertices)):
                k = (j + 1) % len(vertices)
                area += vertices[j].x * vertices[k].y
                area -= vertices[k].x * vertices[j].y
            area = abs(area) / 2.0
            
            if area > 100: # Ignore tiny noise
                print(f"  Path {i}: Closed={is_closed}, Vertices={len(vertices)}, Area(pts)={area:.2f}")

if __name__ == "__main__":
    analyze_pdf(r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\construction-ai-service\tests\pdf_corpus\tier1_easy\15x30-ft-Best-House-Plan-Model.pdf")
    print("-" * 40)
    analyze_pdf(r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\construction-ai-service\tests\pdf_corpus\tier1_easy\20x45-Model.pdf")
