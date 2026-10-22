# test_inference.py
from ultralytics import YOLO
import cv2
import fitz  # PyMuPDF
import numpy as np
from pathlib import Path

MODEL_PATH = r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\runs\segment\constructiq_parser\v1-2\weights\best.pt"

CLASS_NAMES = ['wall','room','door','window',
               'bathroom','kitchen','bedroom','livingroom']
CLASS_COLORS = [
    (0,0,0),        # wall - black
    (173,216,230),  # room - light blue
    (139,69,19),    # door - brown
    (0,255,255),    # window - cyan
    (0,0,255),      # bathroom - blue
    (255,165,0),    # kitchen - orange
    (128,0,128),    # bedroom - purple
    (0,255,0),      # livingroom - green
]

def pdf_to_image(pdf_path, dpi=150):
    doc = fitz.open(pdf_path)
    page = doc[0]
    mat = fitz.Matrix(dpi/72, dpi/72)
    pix = page.get_pixmap(matrix=mat)
    img = np.frombuffer(pix.samples, dtype=np.uint8)
    img = img.reshape(pix.height, pix.width, pix.n)
    if pix.n == 4:
        img = cv2.cvtColor(img, cv2.COLOR_RGBA2RGB)
    return img

def run_inference(input_path, output_path=None):
    model = YOLO(MODEL_PATH)
    
    path = Path(input_path)
    if path.suffix.lower() == '.pdf':
        print(f"Converting PDF to image...")
        img = pdf_to_image(str(path))
        img_path = str(path.with_suffix('.png'))
        cv2.imwrite(img_path, cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
        inference_input = img_path
    else:
        inference_input = str(path)
        img = cv2.imread(inference_input)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    
    print(f"Running inference...")
    results = model(inference_input, conf=0.3, iou=0.5)
    result = results[0]
    
    print(f"\nDETECTIONS:")
    print(f"{'Class':<15} {'Confidence':>12} {'Area (px)':>12}")
    print("-"*42)
    
    class_areas = {}
    if result.masks is not None:
        for i, (box, mask) in enumerate(
                zip(result.boxes, result.masks.data)):
            class_id = int(box.cls[0])
            conf = float(box.conf[0])
            class_name = CLASS_NAMES[class_id]
            mask_np = mask.cpu().numpy()
            area_px = int(mask_np.sum())
            print(f"{class_name:<15} {conf:>12.3f} {area_px:>12,}")
            if class_name not in class_areas:
                class_areas[class_name] = []
            class_areas[class_name].append(area_px)
    else:
        print("No masks detected")
    
    print(f"\nSUMMARY:")
    for cls, areas in class_areas.items():
        print(f"  {cls}: {len(areas)} detected, "
              f"total area {sum(areas):,}px")
    
    # Save visualisation
    vis = result.plot(
        conf=True, labels=True, boxes=True, masks=True)
    
    if output_path is None:
        output_path = str(path.with_name(
            path.stem + '_detected.jpg'))
    
    cv2.imwrite(output_path, vis)
    print(f"\nVisualization saved: {output_path}")
    return class_areas

if __name__ == '__main__':
    # Dynamically find all PDF files in the workspace (ignoring datasets, git, and runs)
    workspace_root = Path(r"c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project")
    ignore_dirs = {'.git', '.agent', '.claude', '.cursor', '.code-review-graph', 'runs', 'cubicasa_yolo', 'cubicasa5k', 'scratch', 'graphify-out'}
    
    test_files = []
    for p in workspace_root.rglob('*.pdf'):
        # Check if the path contains any ignored directory
        parts = p.relative_to(workspace_root).parts
        if not any(ignored in parts for ignored in ignore_dirs):
            test_files.append(p)
            
    print(f"Found {len(test_files)} PDF files to test:")
    for f in test_files:
        print(f"  - {f.relative_to(workspace_root)}")
        
    for f in test_files:
        print(f"\n{'='*50}")
        print(f"Testing: {f.name}")
        print('='*50)
        try:
            run_inference(str(f))
        except Exception as e:
            print(f"Error testing {f.name}: {e}")

