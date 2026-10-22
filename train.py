# train.py
# Optimized training script merging VRAM efficiency, RAM caching, and periodic checkpoints

from ultralytics import YOLO

def main():
    # Load the pre-trained segment model
    model = YOLO('yolov8m-seg.pt')
    
    # Start training with highly optimized configurations
    model.train(
        data=r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\cubicasa_yolo\cubicasa.yaml",
        epochs=100,
        imgsz=512,          # Reduced from 640 — saves ~0.8GB VRAM
        batch=4,            # Small batch for 4GB RTX 3050 VRAM
        cache=True,         # Cache images in RAM (takes advantage of your 16GB system RAM)
        device=0,           # GPU (CUDA device 0)
        amp=True,           # Automatic Mixed Precision — cuts VRAM usage by ~40%
        workers=4,          # Parallel data loading workers
        patience=20,        # Early stopping patience
        save=True,          # Save models
        project="constructiq_parser",
        name="v1",
        save_period=10      # Save checkpoints every 10 epochs for overnight safety
    )

if __name__ == '__main__':
    main()
