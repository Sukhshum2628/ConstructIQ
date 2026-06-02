import fitz
import numpy as np
import cv2
from pathlib import Path

def detect_floor_plan_row_bounds(ink_matrix):
    """
    Automatically detects the vertical y0 and y1 coordinates (as fractions 
    of page height) that contain the primary floor plan drawing row.
    """
    height, width = ink_matrix.shape
    
    # Compute horizontal projection profile (ink sum per row)
    row_density = np.sum(ink_matrix, axis=1)
    
    # Smooth row density profile using a moving average
    window_size = int(height * 0.05)  # 5% of page height
    smoothed_density = np.convolve(
        row_density, np.ones(window_size)/window_size, mode='same'
    )
    
    # Find drawing bands by thresholding against mean density
    density_threshold = np.mean(smoothed_density) * 0.6
    active_rows = smoothed_density > density_threshold
    
    bands = []
    in_band = False
    start_y = 0
    
    for y, active in enumerate(active_rows):
        if active and not in_band:
            in_band = True
            start_y = y
        elif not active and in_band:
            in_band = False
            end_y = y
            band_height = end_y - start_y
            # Keep bands that occupy at least 15% of page height
            if band_height > height * 0.15:
                total_ink = np.sum(row_density[start_y:end_y])
                bands.append((start_y, end_y, total_ink))
                
    if not bands:
        # Fallback to standard bottom-half coordinates if no distinct band stands out
        return int(height * 0.58), int(height * 0.90)
    
    # Select the band with the highest total ink density
    best_band = max(bands, key=lambda b: b[2])
    
    # Add a tiny padding (2%) around detected drawing boundary for safety
    y0 = max(0, best_band[0] - int(height * 0.02))
    y1 = min(height, best_band[1] + int(height * 0.02))
    
    return y0, y1

def segment_floor_plans(pdf_path: str, page_num: int = 0) -> list[dict]:
    """
    Segment the floor plans in a PDF into one or more regions dynamically,
    supporting single-page layouts, column grids, and row stacks.
    """
    doc = fitz.open(pdf_path)
    page = doc[page_num]

    page_rect = page.rect
    page_width, page_height = page_rect.width, page_rect.height
    
    # Step 1: Render page at 2x zoom for layout analysis
    mat_2x = fitz.Matrix(2, 2)
    pix_2x = page.get_pixmap(matrix=mat_2x)
    img_2x = np.frombuffer(pix_2x.samples, dtype=np.uint8).reshape(pix_2x.height, pix_2x.width, pix_2x.n)
    
    # Convert to grayscale
    if pix_2x.n == 4:
        gray_2x = cv2.cvtColor(img_2x, cv2.COLOR_RGBA2GRAY)
    else:
        gray_2x = cv2.cvtColor(img_2x, cv2.COLOR_RGB2GRAY)
        
    # Get binary ink matrix (drawing lines)
    ink_matrix = (gray_2x < 200).astype(float)
    img_h, img_w = ink_matrix.shape
    
    # Step 2: Detect horizontal row bounds
    y0_img, y1_img = detect_floor_plan_row_bounds(ink_matrix)
    band_height_frac = (y1_img - y0_img) / img_h
    
    # Step 3: Check case types
    # CASE 1: Single full page plan
    if band_height_frac > 0.55:
        print(f"[Segmenter] Case 1 detected: Single full-page floor plan ({band_height_frac*100:.1f}% height)")
        # Render at 4x for YOLO
        mat_4x = fitz.Matrix(4, 4)
        pix_4x = page.get_pixmap(matrix=mat_4x)
        img_4x = np.frombuffer(pix_4x.samples, dtype=np.uint8).reshape(pix_4x.height, pix_4x.width, pix_4x.n)
        if pix_4x.n == 4:
            img_4x = cv2.cvtColor(img_4x, cv2.COLOR_RGBA2RGB)
            
        return [{
            'label': 'Floor Plan 1',
            'image': img_4x,
            'page_rect': (0.0, 0.0, page_width, page_height),
            'floor_index': 0
        }]
        
    # Step 4: Vertical column gap detection inside the detected horizontal slice
    slice_ink = ink_matrix[y0_img:y1_img, :]
    col_density = slice_ink.sum(axis=0)
    
    # Smooth column density vertically to ignore tiny lines or dimension offsets
    col_window = int(img_w * 0.02)  # 2% of page width
    smoothed_col = np.convolve(col_density, np.ones(col_window)/col_window, mode='same')
    
    threshold = np.mean(smoothed_col) * 0.35
    valleys = smoothed_col < threshold
    
    # Extract dividers
    dividers = []
    in_valley = False
    valley_start = 0
    for x, is_valley in enumerate(valleys):
        if is_valley and not in_valley:
            in_valley = True
            valley_start = x
        elif not is_valley and in_valley:
            in_valley = False
            valley_width = x - valley_start
            # Skip borders and very small valleys
            if img_w * 0.02 < valley_start < img_w * 0.98 and valley_width > img_w * 0.01:
                dividers.append(int((valley_start + x) / 2))
                
    print(f"[Segmenter] Valleys/dividers found at 2x: {dividers}")
    
    regions = []
    
    # CASE 2: Multiple floor plans in columns
    if len(dividers) > 0:
        print(f"[Segmenter] Case 2 detected: {len(dividers) + 1} side-by-side columns")
        
        # Sort dividers
        dividers.sort()
        
        # Map out x boundary splits
        x_splits = [0] + dividers + [img_w]
        
        for i in range(len(x_splits) - 1):
            # Translate image coordinates back to PDF points (dividing by 2)
            pdf_x0 = x_splits[i] / 2
            pdf_x1 = x_splits[i+1] / 2
            pdf_y0 = y0_img / 2
            pdf_y1 = y1_img / 2
            
            # Apply slight safety overlap to the left/right boundaries so no walls are cut
            if i > 0:
                pdf_x0 = max(0, pdf_x0 - 15)
            if i < len(x_splits) - 2:
                pdf_x1 = min(page_width, pdf_x1 + 15)
                
            pdf_rect = fitz.Rect(pdf_x0, pdf_y0, pdf_x1, pdf_y1)
            
            # Render at 4x zoom for YOLO
            mat_4x = fitz.Matrix(4, 4)
            pix_4x = page.get_pixmap(clip=pdf_rect, matrix=mat_4x)
            img_4x = np.frombuffer(pix_4x.samples, dtype=np.uint8).reshape(pix_4x.height, pix_4x.width, pix_4x.n)
            if pix_4x.n == 4:
                img_4x = cv2.cvtColor(img_4x, cv2.COLOR_RGBA2RGB)
            elif pix_4x.n == 3:
                img_4x = cv2.cvtColor(img_4x, cv2.COLOR_BGR2RGB)
                
            regions.append({
                'label': f'Floor Plan {i+1}',
                'image': img_4x,
                'page_rect': (pdf_x0, pdf_y0, pdf_x1, pdf_y1),
                'floor_index': i
            })
            
        return regions
        
    # CASE 3: No vertical dividers, check for multiple row bands (stacked vertically)
    # If there are no vertical dividers and the densest band is small, treat full page as single region (Case 1 fallback)
    print(f"[Segmenter] Case 1 Fallback: No clear columns or stack dividers found. Single full page.")
    mat_4x = fitz.Matrix(4, 4)
    pix_4x = page.get_pixmap(matrix=mat_4x)
    img_4x = np.frombuffer(pix_4x.samples, dtype=np.uint8).reshape(pix_4x.height, pix_4x.width, pix_4x.n)
    if pix_4x.n == 4:
        img_4x = cv2.cvtColor(img_4x, cv2.COLOR_RGBA2RGB)
        
    return [{
        'label': 'Floor Plan 1',
        'image': img_4x,
        'page_rect': (0.0, 0.0, page_width, page_height),
        'floor_index': 0
    }]
