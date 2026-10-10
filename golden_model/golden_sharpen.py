#!/usr/bin/env python3
"""
Golden model for the 3x3 sharpen convolution accelerator.

This is the independent reference — it must NOT share code with the RTL.
It is the single source of truth for "what is the correct output pixel."

Frozen parameters (see docs/FROZEN_BASELINE.md):
  kernel = [[0,-1,0],[-1,5,-1],[0,-1,0]]
  bias = 0, shift = 0
  zero padding on all borders
  output = clamp(sum, 0, 255)
"""
import numpy as np

KERNEL = np.array([[0, -1, 0],
                    [-1, 5, -1],
                    [0, -1, 0]], dtype=np.int64)
BIAS = 0
SHIFT = 0


def golden_sharpen(img: np.ndarray) -> np.ndarray:
    """img: 2D uint8 array (H x W). Returns uint8 array, same shape."""
    assert img.ndim == 2, "expected a 2D grayscale image"
    H, W = img.shape
    padded = np.pad(img.astype(np.int64), 1, mode="constant", constant_values=0)
    out = np.zeros((H, W), dtype=np.int64)

    for y in range(H):
        for x in range(W):
            window = padded[y:y + 3, x:x + 3]
            s = int(np.sum(window * KERNEL)) + BIAS
            if SHIFT > 0:
                s = s >> SHIFT  # arithmetic right shift, truncating (per spec)
            out[y, x] = s

    out = np.clip(out, 0, 255)
    return out.astype(np.uint8)


def self_check():
    """Hand-verify one pixel against a manual calculation (see project notes)."""
    block = np.array([[10, 20, 30],
                       [40, 50, 60],
                       [70, 80, 90]], dtype=np.int64)
    # 0*10 + -1*20 + 0*30 + -1*40 + 5*50 + -1*60 + 0*70 + -1*80 + 0*90
    # = -20 -40 +250 -60 -80 = 50
    s = int(np.sum(block * KERNEL))
    expected = 50
    assert s == expected, f"self-check failed: got {s}, expected {expected}"
    print(f"[self_check] OK: hand-calculated window -> {s} (expected {expected})")


if __name__ == "__main__":
    self_check()
