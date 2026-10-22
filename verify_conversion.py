# verify_conversion.py
# Run this before training to confirm labels look correct

import os
import random
from pathlib import Path
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from PIL import Image
import numpy as np

OUTPUT_ROOT = r'c:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\cubicasa_yolo'

CLASS_NAMES = ['wall','room','door','window',
               'bathroom','kitchen','bedroom','livingroom']
CLASS_COLORS = ['black','lightblue','brown','cyan',
                'blue','orange','purple','green']

def visualize_sample(img_path, label_path):
    img = Image.open(img_path)
    w, h = img.size
    
    fig, axes = plt.subplots(1, 2, figsize=(16, 8))
    axes[0].imshow(img)
    axes[0].set_title('Original Floor Plan')
    axes[0].axis('off')
    
    axes[1].imshow(img)
    axes[1].set_title('YOLO Annotations')
    axes[1].axis('off')
    
    with open(label_path) as f:
        lines = f.readlines()
    
    class_counts = {}
    for line in lines:
        parts = line.strip().split()
        if not parts:
            continue
        class_id = int(parts[0])
        coords = list(map(float, parts[1:]))
        
        # Convert normalized coords back to pixels
        xs = [coords[i] * w for i in range(0, len(coords), 2)]
        ys = [coords[i] * h for i in range(1, len(coords), 2)]
        
        # Draw polygon
        polygon = plt.Polygon(
            list(zip(xs, ys)),
            fill=True,
            facecolor=CLASS_COLORS[class_id],
            alpha=0.3,
            edgecolor=CLASS_COLORS[class_id],
            linewidth=1
        )
        axes[1].add_patch(polygon)
        
        class_counts[CLASS_NAMES[class_id]] = \
            class_counts.get(CLASS_NAMES[class_id], 0) + 1
    
    title = ', '.join(f'{k}:{v}' for k,v in class_counts.items())
    axes[1].set_title(f'Labels: {title}')
    
    plt.tight_layout()
    plt.savefig('verification_sample.png', dpi=100, 
                bbox_inches='tight')
    plt.close()
    print(f'Saved: verification_sample.png')
    print(f'Annotation counts: {class_counts}')
    print(f'Total annotations: {sum(class_counts.values())}')

# Pick a random training sample
train_imgs = list(
    Path(OUTPUT_ROOT, 'images', 'train').glob('*.png'))
sample_img = random.choice(train_imgs)
sample_lbl = Path(OUTPUT_ROOT, 'labels', 'train') / \
             sample_img.with_suffix('.txt').name

print(f'Checking: {sample_img.name}')
visualize_sample(sample_img, sample_lbl)
