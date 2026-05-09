import fitz
import math
from collections import defaultdict

def analyze_house_plan():
    doc = fitz.open(r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\construction-ai-service\tests\pdf_corpus\tier2_intermediate\house_plan.pdf")
    page = doc[0]
    drawings = page.get_drawings()
    raw_lines = []
    for d in drawings:
        for item in d["items"]:
            if item[0] == "l":
                raw_lines.append(((item[1].x, item[1].y), (item[2].x, item[2].y)))
    
    n = len(raw_lines)
    parent = list(range(n))
    def find(i):
        root = i
        while parent[root] != root: root = parent[root]
        return root
    def union(i, j):
        root_i, root_j = find(i), find(j)
        if root_i != root_j: parent[root_i] = root_j

    pt_map = defaultdict(list)
    for i, (p1, p2) in enumerate(raw_lines):
        if math.dist(p1, p2) > 320: continue
        for p in (p1, p2):
            key = (round(p[0]), round(p[1]))
            pt_map[key].append(i)
    for indices in pt_map.values():
        for i in range(len(indices)-1): union(indices[i], indices[i+1])

    clusters = defaultdict(list)
    for i in range(n): clusters[find(i)].append(i)
    
    island_stats = []
    for root, indices in clusters.items():
        total_len = sum(math.dist(raw_lines[i][0], raw_lines[i][1]) for i in indices)
        xs = [raw_lines[i][0][0] for i in indices] + [raw_lines[i][1][0] for i in indices]
        ys = [raw_lines[i][0][1] for i in indices] + [raw_lines[i][1][1] for i in indices]
        w, h = max(xs)-min(xs), max(ys)-min(ys)
        area_pts = w * h
        island_stats.append((total_len, w, h, area_pts, root))

    island_stats.sort(key=lambda x: x[0], reverse=True)
    
    print("Top 5 Islands by Length:")
    for length, w, h, area, root in island_stats[:5]:
        print(f"Island {root}: Length={length:.1f}, BBox={w:.1f}x{h:.1f}, Area(pts)={area:.1f}")

if __name__ == "__main__":
    analyze_house_plan()
