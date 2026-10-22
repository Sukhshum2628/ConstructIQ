"""Quantize the on-device PDF-parser ONNX model (best.onnx).

Findings (YOLOv8m-seg, opset 12, measured on x86 CPU — verify on your target ARM
device before adopting):

  * Dynamic INT8  -> 28 MB (4x smaller), accuracy preserved, but ~10x SLOWER on
                     CPU (uses the un-optimized ConvInteger path). Only adopt if
                     on-device (ARM) benchmarking shows acceptable latency.
  * Static  INT8  -> 28 MB and ~2.5x FASTER (QLinearConv), but the detection head
                     is too sensitive: with a small calibration set it collapsed
                     to 0 detections. Needs a large, representative calibration
                     set and/or excluding the head nodes from quantization.
  * FP16 (convert)-> 55 MB but the converter mishandles YOLO's Resize nodes and
                     the model fails to load. Re-export from best.pt with
                     `half=True` instead if FP16 is wanted (needs FP16 I/O on the
                     Dart side).

IMPORTANT: this model runs ON-DEVICE, so its size does NOT affect the Render
512MB limit (that was the PyTorch/sentence-transformers dependency, now removed).
Shrinking it only reduces app-bundle size. Production stays FP32 until on-device
benchmarking justifies a swap.

Usage:
    python scripts/quantize_parser_model.py            # produce dynamic-INT8
    # then benchmark best.int8.onnx on the phone; if fast enough, copy it over
    # construction_flutter_app/assets/models/best.onnx
"""
import os
import time

import numpy as np
import onnxruntime as ort
from onnxruntime.quantization import quantize_dynamic, QuantType

SRC = "construction_flutter_app/assets/models/best.onnx"
DST = "construction_flutter_app/assets/models/best.int8.onnx"


def quantize():
    quantize_dynamic(SRC, DST, weight_type=QuantType.QInt8)
    print(f"FP32 {os.path.getsize(SRC)/1e6:.1f} MB -> "
          f"INT8 {os.path.getsize(DST)/1e6:.1f} MB")


def benchmark(path: str, label: str, runs: int = 5):
    sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
    x = np.random.rand(1, 3, 512, 512).astype(np.float32)
    sess.run(None, {"images": x})  # warmup
    times = []
    for _ in range(runs):
        t0 = time.time()
        sess.run(None, {"images": x})
        times.append((time.time() - t0) * 1000)
    print(f"{label}: {np.mean(times):.0f} ms (min {min(times):.0f})")


if __name__ == "__main__":
    quantize()
    benchmark(SRC, "FP32")
    benchmark(DST, "INT8 (dynamic)")
    print("\nBenchmark best.int8.onnx on the ARM device before adopting it.")
