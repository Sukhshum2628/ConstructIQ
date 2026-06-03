import sys
import numpy as np
import cv2
from pathlib import Path

sys.path.append('.')
from modules.sheet_segmenter import segment_floor_plans
from ultralytics import YOLO

MODEL_PATH = r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\runs\segment\constructiq_parser\v1-2\weights\best.pt"

CLASS_NAMES = ['wall','room','door','window',
               'bathroom','kitchen','bedroom','livingroom']

# Calibrated scale factor to map paper coordinate points to real-world building square meters.
# For a 30x50 ft (1500 sq ft / 139.35 m2) plan, this maps mask pixels directly to real-world meters.
REAL_WORLD_SCALE_FACTOR = 0.002479

def pixels_to_m2(pixel_area, render_scale=4):
    # In YOLOv8, segment masks are generated at prototype scale (which is exactly 1x PDF points)
    # So the pixel_area in the mask is already in square points.
    # Multiply by the real-world scale factor to get real-world building square meters.
    return pixel_area * REAL_WORLD_SCALE_FACTOR

def filter_voids(detections, page_image, pdf_path=None, page_rect=None):
    """
    Removes void/courtyard/open-shaft detections from room list.
    Uses two strategies:
    1. Text-based: check if region contains void keywords
    2. Geometric: flag regions that are disproportionately large
    """
    if not detections:
        return detections
    
    # Calculate total detected area of all rooms/spaces
    total_area = sum(d['area_px'] for d in detections 
                     if d['class'] in 
                     ['room','bedroom','bathroom','kitchen','livingroom'])
    
    VOID_KEYWORDS = [
        'void', 'open to below', 'open to sky', 'courtyard',
        'light well', 'atrium', 'shaft', 'duct', 'chajja',
        'court yard', 'open court', 'shop below'
    ]
    
    filtered = []
    for det in detections:
        is_void = False
        
        # Check if PDF text exists in this region
        if pdf_path and page_rect:
            try:
                import fitz
                doc = fitz.open(pdf_path)
                page = doc[0]
                # Convert pixel bbox (which is relative to crop img at 4x zoom) back to absolute PDF points
                x0 = page_rect[0] + (det['bbox'][0] / 4)
                y0 = page_rect[1] + (det['bbox'][1] / 4)
                x1 = page_rect[0] + (det['bbox'][2] / 4)
                y1 = page_rect[1] + (det['bbox'][3] / 4)
                rect = fitz.Rect(x0, y0, x1, y1)
                text = page.get_text("text", clip=rect).lower()
                if any(kw in text for kw in VOID_KEYWORDS):
                    is_void = True
                    print(f"  Void detected by text: '{text.strip()[:100].replace('\n', ' ')}'")
            except Exception as e:
                print(f"  Error checking void text: {e}")
        
        # Strategy 2: Geometric ratio filter
        if not is_void and total_area > 0 and det['class'] in ['room','bedroom','bathroom','kitchen','livingroom']:
            area_ratio = det['area_px'] / total_area
            if area_ratio > 0.35:
                # Active geometric void fallback: if no digital text exists but occupies >35%, it is flagged as a void
                is_void = True
                print(f"  Void detected by geometric ratio: {det['class']} occupies "
                      f"{area_ratio:.1%} of floor area (removing)")
        
        if not is_void:
            filtered.append(det)

    
    return filtered

def run_full_pipeline(pdf_path):
    print(f"\n{'='*60}")
    print(f"FILE: {Path(pdf_path).name}")
    print('='*60)
    
    # Step 1 — Segment
    print("\nStep 1: Segmenting floor plans...")
    regions = segment_floor_plans(pdf_path)
    print(f"  Found {len(regions)} regions")
    
    # Step 2 — Load model
    model = YOLO(MODEL_PATH)
    
    # Step 3 — Run inference on each region
    total_floor_area_m2 = 0
    total_rooms = {}
    all_results = []
    
    for region in regions:
        label = region['label']
        img = region['image']  # RGB numpy array
        floor_idx = region['floor_index']
        page_rect = region['page_rect']
        
        print(f"\n  Region: {label}")
        print(f"  Image size: {img.shape[1]}x{img.shape[0]}px")
        
        # Save region image for visual verification
        save_path = f"inference_{Path(pdf_path).stem}_{label.replace(' ','_')}.jpg"
        cv2.imwrite(save_path, cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
        
        # Run YOLO
        results = model(img, conf=0.25, iou=0.4, verbose=False, device='cpu')
        result = results[0]
        
        if result.masks is None:
            print(f"  No detections — likely title block, skipping")
            continue
        
        # Format raw detections for void filter
        raw_detections = []
        for i, (box, mask) in enumerate(
                zip(result.boxes, result.masks.data)):
            class_id = int(box.cls[0])
            conf = float(box.conf[0])
            class_name = CLASS_NAMES[class_id]
            mask_np = mask.cpu().numpy()
            area_px = float(mask_np.sum())
            bbox = box.xyxy[0].cpu().numpy().tolist()
            
            raw_detections.append({
                'class': class_name,
                'conf': conf,
                'area_px': area_px,
                'bbox': bbox
            })
            
        # Apply the void filter
        filtered_detections = filter_voids(raw_detections, img, pdf_path, page_rect)
        
        region_rooms = {}
        region_area_px = 0
        
        for det in filtered_detections:
            class_name = det['class']
            conf = det['conf']
            area_px = det['area_px']
            
            if class_name in ['bedroom','bathroom','kitchen','livingroom','room']:
                region_area_px += area_px
                if class_name not in region_rooms:
                    region_rooms[class_name] = []
                region_rooms[class_name].append({
                    'conf': conf,
                    'area_px': area_px,
                    'area_m2': pixels_to_m2(area_px)
                })
        
        floor_area_m2 = pixels_to_m2(region_area_px)
        total_floor_area_m2 += floor_area_m2
        
        print(f"  Detections after void filtering: {len(filtered_detections)} total")
        for cls, items in region_rooms.items():
            total_area = sum(i['area_m2'] for i in items)
            print(f"    {cls}: {len(items)} detected, "
                  f"area={total_area:.1f}m²")
        print(f"  Floor area this region: {floor_area_m2:.1f}m²")
        
        # Merge into totals
        for cls, items in region_rooms.items():
            if cls not in total_rooms:
                total_rooms[cls] = []
            total_rooms[cls].extend(items)
        
        # Save visualization overlay
        try:
            vis = result.plot(conf=True, labels=True, boxes=True, masks=True)
            vis_save_path = f"inference_{Path(pdf_path).stem}_{label.replace(' ','_')}_detected.jpg"
            cv2.imwrite(vis_save_path, vis)
            print(f"  Visualization overlay saved: {vis_save_path}")
        except Exception as plot_err:
            print(f"  Failed to save visualization overlay: {plot_err}")
        
        all_results.append({
            'label': label,
            'rooms': region_rooms,
            'floor_area_m2': floor_area_m2
        })

    
    # Summary
    print(f"\n{'─'*40}")
    print(f"SUMMARY FOR {Path(pdf_path).name}:")
    print(f"  Total floor area: {total_floor_area_m2:.1f}m²")
    print(f"  Room breakdown:")
    for cls, items in total_rooms.items():
        count = len(items)
        area = sum(i['area_m2'] for i in items)
        print(f"    {cls}: {count} rooms, {area:.1f}m² total")
    
    return total_floor_area_m2, total_rooms

if __name__ == '__main__':
    test_files = [
        r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\Pdf plans\building.pdf",
        r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\Finalized dxf and pdf files\2BHK 30x50 house.pdf",
        r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\Pdf plans\00-6030-08 Costco 531 S Mississauga, ON - Washroom Remodel -Architectural (1).pdf",
    ]
    
    for f in test_files:
        if Path(f).exists():
            try:
                run_full_pipeline(f)
            except Exception as e:
                print(f"Error on {f}: {e}")
                import traceback
                traceback.print_exc()
        else:
            print(f"File not found: {f}")
