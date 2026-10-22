# cubicasa_to_yolo.py
# Converts CubiCasa5K SVG annotations to YOLO segmentation format
# Run from the cubicasa5k root directory

import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
import numpy as np

# ── CLASS DEFINITIONS ─────────────────────────────────
# We use 8 classes for both structural and interior estimation
CLASS_MAP = {
    'wall':       0,   # all Wall elements
    'room':       1,   # generic room (Undefined, Outdoor, etc.)
    'door':       2,   # all Door elements
    'window':     3,   # all Window elements
    'bathroom':   4,   # Bath, Bath Shower, WC
    'kitchen':    5,   # Kitchen
    'bedroom':    6,   # Bedroom
    'livingroom': 7,   # LivingRoom, Dining, DraughtLobby
}

ROOM_TYPE_TO_CLASS = {
    'Bath':          4,
    'BathShower':    4,
    'Undefined':     1,
    'Outdoor':       1,
    'Kitchen':       5,
    'Bedroom':       6,
    'LivingRoom':    7,
    'Dining':        7,
    'DraughtLobby':  7,
    'Closet':        1,
    'ClosetWalkIn':  1,
    'Corridor':      1,
    'Garage':        1,
    'Balcony':       1,
    'Storage':       1,
    'TechnicalRoom': 1,
}

NS = {'svg': 'http://www.w3.org/2000/svg'}

def parse_points(points_str):
    """Parse SVG polygon points string to list of (x,y) tuples."""
    coords = re.findall(r'[-\d.]+', points_str)
    points = []
    for i in range(0, len(coords) - 1, 2):
        points.append((float(coords[i]), float(coords[i+1])))
    return points

def normalize_polygon(points, img_w, img_h):
    """Normalize polygon points to 0-1 range for YOLO."""
    normalized = []
    for x, y in points:
        nx = max(0.0, min(1.0, x / img_w))
        ny = max(0.0, min(1.0, y / img_h))
        normalized.extend([nx, ny])
    return normalized

def polygon_to_yolo_line(class_id, points, img_w, img_h):
    """Convert polygon to YOLO segmentation format line."""
    if len(points) < 3:
        return None
    normalized = normalize_polygon(points, img_w, img_h)
    coords_str = ' '.join(f'{c:.6f}' for c in normalized)
    return f'{class_id} {coords_str}'

def get_room_class(space_class_str):
    """Extract room class ID from SVG class attribute."""
    # class attribute looks like "Space Bedroom" or "Space Bath Shower"
    parts = space_class_str.replace('Space', '').strip().split()
    room_type = ''.join(parts)  # e.g. "BathShower", "Bedroom"
    return ROOM_TYPE_TO_CLASS.get(room_type, 1)  # default to generic room

def parse_svg_to_yolo(svg_path, img_w, img_h):
    """Parse one SVG annotation file and return YOLO format lines."""
    tree = ET.parse(svg_path)
    root = tree.getroot()
    
    yolo_lines = []
    
    # ── Parse all elements recursively ────────────────
    for elem in root.iter():
        tag = elem.tag.replace('{http://www.w3.org/2000/svg}', '')
        class_attr = elem.get('class', '')
        
        # Skip non-structural elements
        if 'FixedFurniture' in class_attr:
            continue
        if 'SelectionControls' in class_attr:
            continue
        if 'Dimension' in class_attr:
            continue
            
        # ── SPACES (rooms) ────────────────────────────
        if tag == 'g' and class_attr.startswith('Space'):
            room_class = get_room_class(class_attr)
            # Find the first direct polygon child
            for child in elem:
                child_tag = child.tag.replace(
                    '{http://www.w3.org/2000/svg}', '')
                if child_tag == 'polygon':
                    pts_str = child.get('points', '')
                    if pts_str:
                        points = parse_points(pts_str)
                        line = polygon_to_yolo_line(
                            room_class, points, img_w, img_h)
                        if line:
                            yolo_lines.append(line)
                    break  # only the first polygon is the boundary
        
        # ── WALLS ─────────────────────────────────────
        elif tag == 'g' and ('Wall External' in class_attr 
                              or class_attr == 'Wall'):
            for child in elem:
                child_tag = child.tag.replace(
                    '{http://www.w3.org/2000/svg}', '')
                if child_tag == 'polygon':
                    pts_str = child.get('points', '')
                    if pts_str:
                        points = parse_points(pts_str)
                        # Filter out tiny noise polygons
                        if len(points) >= 3:
                            line = polygon_to_yolo_line(
                                CLASS_MAP['wall'], 
                                points, img_w, img_h)
                            if line:
                                yolo_lines.append(line)
                    break
        
        # ── DOORS ─────────────────────────────────────
        elif tag == 'g' and class_attr.startswith('Door'):
            for child in elem:
                child_tag = child.tag.replace(
                    '{http://www.w3.org/2000/svg}', '')
                child_class = child.get('class', '')
                if child_tag == 'g' and 'Threshold' in child_class:
                    for grandchild in child:
                        gc_tag = grandchild.tag.replace(
                            '{http://www.w3.org/2000/svg}', '')
                        if gc_tag == 'polygon':
                            pts_str = grandchild.get('points', '')
                            if pts_str:
                                points = parse_points(pts_str)
                                line = polygon_to_yolo_line(
                                    CLASS_MAP['door'],
                                    points, img_w, img_h)
                                if line:
                                    yolo_lines.append(line)
                            break
                    break
        
        # ── WINDOWS ───────────────────────────────────
        elif tag == 'g' and class_attr.startswith('Window'):
            for child in elem:
                child_tag = child.tag.replace(
                    '{http://www.w3.org/2000/svg}', '')
                if child_tag == 'polygon':
                    pts_str = child.get('points', '')
                    if pts_str:
                        points = parse_points(pts_str)
                        line = polygon_to_yolo_line(
                            CLASS_MAP['window'],
                            points, img_w, img_h)
                        if line:
                            yolo_lines.append(line)
                    break
    
    return yolo_lines

def process_split(split_file, cubicasa_root, output_root, split_name):
    """Process one split (train/val/test)."""
    split_path = Path(cubicasa_root) / split_file
    
    img_output = Path(output_root) / 'images' / split_name
    lbl_output = Path(output_root) / 'labels' / split_name
    img_output.mkdir(parents=True, exist_ok=True)
    lbl_output.mkdir(parents=True, exist_ok=True)
    
    with open(split_path) as f:
        folder_list = [line.strip().strip('/') for line in f if line.strip()]
    
    success = 0
    failed = 0
    
    for folder_path in folder_list:
        # folder_path is like "high_quality_architectural/566"
        full_folder = Path(cubicasa_root) / 'cubicasa5k' / folder_path
        
        img_src = full_folder / 'F1_scaled.png'
        svg_src = full_folder / 'model'  # no extension in dataset
        
        if not img_src.exists():
            failed += 1
            continue
        if not svg_src.exists():
            # Try with .svg extension
            svg_src = full_folder / 'model.svg'
            if not svg_src.exists():
                failed += 1
                continue
        
        try:
            # Get image dimensions
            with Image.open(img_src) as img:
                img_w, img_h = img.size
            
            # Parse SVG annotations
            yolo_lines = parse_svg_to_yolo(svg_src, img_w, img_h)
            
            if not yolo_lines:
                failed += 1
                continue
            
            # Create safe filename from folder path
            safe_name = folder_path.replace('/', '_')
            
            # Copy image
            import shutil
            shutil.copy2(img_src, img_output / f'{safe_name}.png')
            
            # Write YOLO label file
            label_file = lbl_output / f'{safe_name}.txt'
            with open(label_file, 'w') as f:
                f.write('\n'.join(yolo_lines))
            
            success += 1
            
            if success % 100 == 0:
                print(f'  {split_name}: {success} processed...')
                
        except Exception as e:
            failed += 1
            if failed <= 5:
                print(f'  Failed on {folder_path}: {e}')
    
    print(f'{split_name}: {success} success, {failed} failed')
    return success

def create_yaml(output_root):
    """Create the YOLO dataset YAML file."""
    yaml_content = f"""# ConstructIQ Floor Plan Dataset
# Converted from CubiCasa5K

path: {output_root}
train: images/train
val: images/val
test: images/test

nc: 8
names:
  0: wall
  1: room
  2: door
  3: window
  4: bathroom
  5: kitchen
  6: bedroom
  7: livingroom
"""
    yaml_path = Path(output_root) / 'cubicasa.yaml'
    with open(yaml_path, 'w') as f:
        f.write(yaml_content)
    print(f'Created: {yaml_path}')

def main():
    # ── CONFIGURE THESE PATHS ─────────────────────────
    CUBICASA_ROOT = r'c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\cubicasa5k'
    OUTPUT_ROOT   = r'c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\cubicasa_yolo'
    # ─────────────────────────────────────────────────
    
    print('CubiCasa5K → YOLO Conversion')
    print('='*50)
    print(f'Input:  {CUBICASA_ROOT}')
    print(f'Output: {OUTPUT_ROOT}')
    print()
    
    splits = [
        ('train.txt', 'train'),
        ('val.txt',   'val'),
        ('test.txt',  'test'),
    ]
    
    total = 0
    for split_file, split_name in splits:
        print(f'Processing {split_name}...')
        n = process_split(
            split_file, CUBICASA_ROOT, OUTPUT_ROOT, split_name)
        total += n
    
    create_yaml(OUTPUT_ROOT)
    
    print()
    print(f'Done. Total converted: {total}')
    print(f'Output directory: {OUTPUT_ROOT}')
    print()
    print('Next step: train YOLOv8m-seg with:')
    print(f'  yolo segment train \\')
    print(f'    model=yolov8m-seg.pt \\')
    print(f'    data={OUTPUT_ROOT}/cubicasa.yaml \\')
    print(f'    imgsz=512 \\')
    print(f'    batch=4 \\')
    print(f'    epochs=100 \\')
    print(f'    amp=True \\')
    print(f'    device=0')

if __name__ == '__main__':
    main()
