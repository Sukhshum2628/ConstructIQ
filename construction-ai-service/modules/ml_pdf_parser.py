import numpy as np
import cv2
import fitz
import re
import os
from pathlib import Path
from .sheet_segmenter import segment_floor_plans

# Import guard to handle case where onnxruntime is not yet installed locally
try:
    import onnxruntime as ort
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False

CLASS_NAMES = ['wall','room','door','window',
               'bathroom','kitchen','bedroom','livingroom']

ROOM_CLASSES = {'room','bathroom','kitchen','bedroom','livingroom'}

MODEL_PATH = Path(__file__).parent.parent / 'models' / 'best.onnx'

# Lazy load — only load model on first inference call
_session = None

def _get_session():
    global _session
    if not ONNX_AVAILABLE:
        raise RuntimeError(
            'onnxruntime not installed. '
            'Run: pip install onnxruntime==1.18.0'
        )
    if _session is None:
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 1
        opts.intra_op_num_threads = 2
        opts.graph_optimization_level = (
            ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        )
        _session = ort.InferenceSession(
            str(MODEL_PATH),
            sess_options=opts,
            providers=['CPUExecutionProvider']
        )
    return _session


def _detect_scale_from_pdf(pdf_path: str, page_num: int = 0) -> float:
    """
    Extract scale from embedded PDF text.
    Returns m_per_point conversion factor.
    Default is 0.0003528 (1:1 — 1pt = 0.3528mm).
    """
    try:
        doc = fitz.open(pdf_path)
        page = doc[page_num]
        words = page.get_text('words')
        
        # Look for scale text like '1:50', '1:100', '1:200'
        scale_ratio = None
        for i, w in enumerate(words):
            if w[4].upper() in ('SCALE:', 'SCALE'):
                # Check next word for ratio
                for j in range(i+1, min(i+4, len(words))):
                    match = re.match(r'1[:/](\d+)', words[j][4])
                    if match:
                        scale_ratio = int(match.group(1))
                        break
            # Direct match on ratio format
            match = re.match(r'^1[:/](\d+)$', w[4])
            if match:
                scale_ratio = int(match.group(1))
        
        if scale_ratio:
            # 1pt = 0.3528mm paper
            # At 1:scale_ratio, 1pt = 0.3528 * scale_ratio mm real
            m_per_point = (0.3528 * scale_ratio) / 1000.0
            return m_per_point
            
    except Exception:
        pass
    
    # Default: assume 1:75 fallback for Indian residential drawings
    return 0.02646  # 1:75


def _preprocess_image(img: np.ndarray, size: int = 512):
    """Preprocess image for ONNX inference."""
    h, w = img.shape[:2]
    # Letterbox resize
    scale = size / max(h, w)
    new_h, new_w = int(h * scale), int(w * scale)
    resized = cv2.resize(img, (new_w, new_h))
    
    # Pad to square
    padded = np.zeros((size, size, 3), dtype=np.uint8)
    padded[:new_h, :new_w] = resized
    
    # Normalize and transpose to NCHW
    tensor = padded.astype(np.float32) / 255.0
    tensor = np.transpose(tensor, (2, 0, 1))
    tensor = np.expand_dims(tensor, 0)
    
    return tensor, scale, new_h, new_w


def _run_onnx_inference(img: np.ndarray, conf_thresh: float = 0.25):
    """
    Run ONNX inference on a single image.
    Returns list of detections: [{class_id, conf, mask, bbox}]
    """
    session = _get_session()
    orig_h, orig_w = img.shape[:2]
    
    tensor, scale, new_h, new_w = _preprocess_image(img)
    
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: tensor})
    
    # YOLOv8-seg ONNX output format:
    # outputs[0]: boxes [1, 44, 5376] (x,y,w,h, 8 class scores, 32 mask coeffs)
    # outputs[1]: protos [1, 32, 128, 128]
    
    if len(outputs) < 2:
        return []
    
    boxes_output = outputs[0][0]  # [44, 5376]
    protos = outputs[1][0]        # [32, 128, 128]
    
    num_detections = boxes_output.shape[1]
    
    cand_boxes = []
    cand_confidences = []
    cand_class_ids = []
    cand_mask_coeffs = []
    
    num_classes = 8
    
    for i in range(num_detections):
        detection = boxes_output[:, i]
        class_scores = detection[4:4+num_classes]
        class_id = int(np.argmax(class_scores))
        conf = float(class_scores[class_id])
        
        if conf < conf_thresh:
            continue
            
        cx, cy, bw, bh = detection[:4]
        # Convert center coordinates to top-left coordinates for NMS
        x = cx - bw / 2
        y = cy - bh / 2
        
        cand_boxes.append([float(x), float(y), float(bw), float(bh)])
        cand_confidences.append(float(conf))
        cand_class_ids.append(class_id)
        cand_mask_coeffs.append(detection[4+num_classes:4+num_classes+32])
        
    if not cand_boxes:
        return []
        
    # Apply Non-Maximum Suppression (NMS)
    indices = cv2.dnn.NMSBoxes(cand_boxes, cand_confidences, score_threshold=conf_thresh, nms_threshold=0.45)
    
    if len(indices) == 0:
        return []
        
    if isinstance(indices[0], (list, np.ndarray)):
        indices = [int(idx[0]) for idx in indices]
    else:
        indices = [int(idx) for idx in indices]
        
    detections = []
    for idx in indices:
        class_id = cand_class_ids[idx]
        conf = cand_confidences[idx]
        x, y, bw, bh = cand_boxes[idx]
        mask_coeffs = cand_mask_coeffs[idx]
        
        # Scale bounding box back to original image size correctly
        x1 = x / scale
        y1 = y / scale
        x2 = (x + bw) / scale
        y2 = (y + bh) / scale
        
        # Filter out massive false room outlines that cover almost the entire drawing region
        box_w = x2 - x1
        box_h = y2 - y1
        if CLASS_NAMES[class_id] in ROOM_CLASSES:
            if box_w > 0.75 * orig_w and box_h > 0.75 * orig_h:
                continue
        
        # Clip coordinates to original image size
        x1i = max(0, int(round(x1)))
        y1i = max(0, int(round(y1)))
        x2i = min(orig_w, int(round(x2)))
        y2i = min(orig_h, int(round(y2)))
        
        # Generate mask from prototype
        mask = np.zeros((128, 128), dtype=np.float32)
        for j in range(32):
            mask += mask_coeffs[j] * protos[j]
            
        # Sigmoid activation
        mask = 1 / (1 + np.exp(-mask))
        
        # Resize mask from 128x128 to 512x512
        mask_padded = cv2.resize(mask, (512, 512), interpolation=cv2.INTER_LINEAR)
        # Crop mask to active letterboxed region
        mask_active = mask_padded[:new_h, :new_w]
        # Resize active mask to original image dimensions
        mask_resized = cv2.resize(mask_active, (orig_w, orig_h), interpolation=cv2.INTER_LINEAR)
        
        # Threshold to get binary mask
        mask_binary = (mask_resized > 0.5).astype(np.uint8)
        
        # Zero out mask outside the bounding box to prevent bleed
        mask_cropped = np.zeros_like(mask_binary)
        mask_cropped[y1i:y2i, x1i:x2i] = mask_binary[y1i:y2i, x1i:x2i]
        
        area_px = float(mask_cropped.sum())
        
        detections.append({
            'class_id': class_id,
            'class_name': CLASS_NAMES[class_id],
            'conf': conf,
            'bbox': (x1, y1, x2, y2),
            'area_px': area_px,
            'mask': mask_cropped,
        })
        
    # Containment Filter: Remove large outer room outlines that contain smaller room/bathroom detections
    detections.sort(key=lambda d: d['area_px'], reverse=True)
    keep = [True] * len(detections)
    
    for i in range(len(detections)):
        if not keep[i] or detections[i]['class_name'] not in ROOM_CLASSES:
            continue
        
        x1_A, y1_A, x2_A, y2_A = detections[i]['bbox']
        
        for j in range(i + 1, len(detections)):
            if not keep[j] or detections[j]['class_name'] not in ROOM_CLASSES:
                continue
                
            x1_B, y1_B, x2_B, y2_B = detections[j]['bbox']
            
            # Check if box B is substantially inside box A
            tol = 30.0  # tolerance in pixels
            if (x1_A - tol <= x1_B and y1_A - tol <= y1_B and 
                x2_A + tol >= x2_B and y2_A + tol >= y2_B):
                # Only discard Box A if it is a generic 'room' class OR matches Box B's class
                if (detections[i]['class_name'] == 'room' or 
                    detections[i]['class_name'] == detections[j]['class_name']):
                    Box_A_contains_B = True
                    keep[i] = False
                    break
                
    filtered_detections = [d for idx, d in enumerate(detections) if keep[idx]]
    return filtered_detections


def _filter_voids(detections: list, total_area_px: float) -> list:
    """Remove void/courtyard false positives."""
    if not detections or total_area_px == 0:
        return detections
    
    filtered = []
    for det in detections:
        if det['class_name'] not in ROOM_CLASSES:
            filtered.append(det)
            continue
        ratio = det['area_px'] / total_area_px
        if ratio > 0.35:
            continue  # likely a void
        filtered.append(det)
    return filtered


def parse_pdf_ml(
    pdf_path: str,
    target_page: int = None
) -> dict:
    """
    Main entry point. Parses a PDF using ML pipeline.
    Returns dict compatible with existing estimation engine schema.
    """
    doc = fitz.open(pdf_path)
    num_pages = len(doc)
    
    # Step 1: Dynamically determine the best page to parse if not specified
    if target_page is None:
        if num_pages == 1:
            target_page = 0
        else:
            best_page = 0
            best_score = -9999
            for p_idx in range(num_pages):
                page = doc[p_idx]
                text = page.get_text().upper()
                
                # Rigid plan check — if there's no word PLAN, it is not a plan page!
                if "PLAN" not in text:
                    score = -9999
                else:
                    score = 0
                    if "PLAN" in text or "FLOOR" in text or "LEVEL" in text:
                        score += 15
                    if "SCALE" in text:
                        score += 15
                    if "REMODEL" in text or "ARCHITECTURAL" in text:
                        score += 10
                    
                    # Direct floor/washroom plan boost
                    if "FLOOR PLAN" in text or "WASHROOM PLAN" in text or "KEY PLAN" in text or "DEMOLITION PLAN" in text or "REMODEL PLAN" in text:
                        score += 100
                        
                    # Detail/Elevation/Schedule penalties
                    if "ELEVATION" in text or "SECTION" in text or "SCHEDULE" in text or "DETAIL" in text:
                        score -= 50
                    
                    # Word count density score
                    words = page.get_text('words')
                    score += min(len(words) // 40, 15)
                    
                    # Check if page has valid floor plan segmentation regions
                    try:
                        regions = segment_floor_plans(pdf_path, page_num=p_idx)
                        num_valid_regions = len([r for r in regions if 'title' not in r['label'].lower()])
                        score += num_valid_regions * 25
                    except Exception:
                        pass
                
                if score > best_score:
                    best_score = score
                    best_page = p_idx
            target_page = best_page

    # Detect scale on the chosen target page
    m_per_point = _detect_scale_from_pdf(pdf_path, page_num=target_page)
    
    # Segment floor plans from the chosen target page
    regions = segment_floor_plans(pdf_path, page_num=target_page)
    
    if not regions:
        return _fallback_result()
    
    total_floor_area_m2 = 0.0
    total_wall_length_m = 0.0
    room_counts = {
        'bathroom': 0,
        'kitchen': 0,
        'bedroom': 0,
        'livingroom': 0,
        'room': 0,
    }
    floor_count = len([r for r in regions
                       if 'title' not in r['label'].lower()])
    
    all_rooms = []
    
    for region in regions:
        img = region['image']
        page_rect = region['page_rect']
        
        # Region Filter: Exclude demolition, ceiling, notes, and schedules columns
        try:
            # Extract text from the core region only (shrink width by 20 points on both sides)
            rect = fitz.Rect(page_rect[0] + 20, page_rect[1], page_rect[2] - 20, page_rect[3])
            text_in_rect = doc[target_page].get_text('text', clip=rect).upper()
            
            # Exclude demolition plans
            if "DEMO" in text_in_rect or "DEMOLITION" in text_in_rect:
                continue
                
            # Exclude ceiling plans
            if "CEILING" in text_in_rect or "REFLECTED" in text_in_rect:
                continue
                
            # Exclude note or schedule columns that do not contain room labels
            if any(k in text_in_rect for k in ["NOTE", "SCHEDULE", "SPECIFICATION", "LEGEND"]):
                if not any(r in text_in_rect for r in ["WOMEN", "MEN", "RESTROOM", "WASHROOM", "TOILET", "ROOM", "OFFICE", "PLAN"]):
                    continue
        except Exception:
            pass
        
        # Run ONNX inference
        detections = _run_onnx_inference(img)
        
        if not detections:
            continue
        
        # Calculate render scale for this region
        # page_rect is in PDF points, img is at 4x render
        rect_width_pt = page_rect[2] - page_rect[0]
        img_width_px = img.shape[1]
        pt_per_px = rect_width_pt / img_width_px
        
        # Area conversion: px² → pt² → m²
        m2_per_px2 = (pt_per_px * m_per_point) ** 2
        
        # Filter room detections
        room_dets = [d for d in detections
                     if d['class_name'] in ROOM_CLASSES]
        total_room_px = sum(d['area_px'] for d in room_dets)
        
        filtered = _filter_voids(room_dets, total_room_px)
        
        region_area = 0.0
        for det in filtered:
            area_m2 = det['area_px'] * m2_per_px2
            region_area += area_m2
            cls = det['class_name']
            if cls in room_counts:
                room_counts[cls] += 1
            all_rooms.append({
                'type': cls,
                'area': round(area_m2, 2),
                'confidence': round(det['conf'], 3),
            })
        
        # Estimate wall length from wall detections
        wall_dets = [d for d in detections
                     if d['class_name'] == 'wall']
        for wd in wall_dets:
            # Approximate wall length from bbox
            x1, y1, x2, y2 = wd['bbox']
            wall_len_px = max(x2 - x1, y2 - y1)
            wall_len_m = wall_len_px * (pt_per_px * m_per_point)
            total_wall_length_m += wall_len_m
        
        total_floor_area_m2 += region_area
    
    # Calculate wall surface area
    # Wall surface area = total_wall_length × ceiling_height
    # Standard commercial ceiling height: 2.7m
    ceiling_height_m = 2.7
    total_wall_area_m2 = total_wall_length_m * ceiling_height_m
    
    # Determine confidence based on scale detection
    has_scale = m_per_point != 0.03528  # not default
    confidence = 0.85 if has_scale else 0.55
    
    return {
        'totalFloorArea': round(total_floor_area_m2, 2),
        'totalWallLength': round(total_wall_length_m, 2),
        'totalWallArea': round(total_wall_area_m2, 2),
        'floorCount': max(1, floor_count),
        'roomBreakdown': all_rooms,
        'roomCounts': room_counts,
        'doorCount': sum(1 for r in regions
                        for d in _run_onnx_inference(r['image'])
                        if d['class_name'] == 'door'),
        'confidence': confidence,
        'scaleDetected': has_scale,
        'scaleUsed': f'1:{round(m_per_point * 1000 / 0.3528)}',
        'parserType': 'ml_pdf',
        'areaSource': 'YOLOv8-seg ML inference',
    }


def _fallback_result() -> dict:
    return {
        'totalFloorArea': 0.0,
        'totalWallLength': 0.0,
        'floorCount': 1,
        'roomBreakdown': [],
        'confidence': 0.1,
        'parserType': 'ml_pdf_failed',
        'areaSource': 'No regions detected',
        'error': 'Sheet segmentation returned no regions',
    }

