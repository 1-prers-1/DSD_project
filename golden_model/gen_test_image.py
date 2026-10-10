#!/usr/bin/env python3
"""
Generates test images + golden expected outputs, written as plain hex
files that the SystemVerilog testbench reads with $readmemh.

Usage:
  python3 gen_test_image.py --size 8 --pattern random --seed 1 --name t0
  python3 gen_test_image.py --size 4 --pattern impulse --name t_small

Produces (into golden_model/vectors/):
  <name>_input.hex       -- W*H lines, one 2-hex-digit pixel per line, raster order
  <name>_expected.hex    -- same format, golden sharpened output
  <name>_meta.txt         -- human-readable: size, pattern, seed
"""
import argparse
import os
import numpy as np
from golden_sharpen import golden_sharpen

OUT_DIR = os.path.join(os.path.dirname(__file__), "vectors")


def make_pattern(size, pattern, seed):
    rng = np.random.default_rng(seed)
    if pattern == "random":
        img = rng.integers(0, 256, size=(size, size), dtype=np.uint8)
    elif pattern == "constant":
        img = np.full((size, size), 128, dtype=np.uint8)
    elif pattern == "impulse":
        img = np.zeros((size, size), dtype=np.uint8)
        img[size // 2, size // 2] = 255
    elif pattern == "ramp":
        row = np.linspace(0, 255, size, dtype=np.uint8)
        img = np.tile(row, (size, 1))
    elif pattern == "checkerboard":
        img = np.zeros((size, size), dtype=np.uint8)
        img[::2, ::2] = 255
        img[1::2, 1::2] = 255
    elif pattern == "all_zero":
        img = np.zeros((size, size), dtype=np.uint8)
    elif pattern == "all_max":
        img = np.full((size, size), 255, dtype=np.uint8)
    else:
        raise ValueError(f"unknown pattern {pattern}")
    return img


def write_hex(path, img):
    with open(path, "w") as f:
        for v in img.flatten(order="C"):  # raster order: row-major
            f.write(f"{v:02x}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=8)
    ap.add_argument("--pattern", default="random",
                     choices=["random", "constant", "impulse", "ramp",
                              "checkerboard", "all_zero", "all_max"])
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--name", default=None, help="base filename (default: pattern_size)")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    name = args.name or f"{args.pattern}_{args.size}x{args.size}"

    img = make_pattern(args.size, args.pattern, args.seed)
    expected = golden_sharpen(img)

    in_path = os.path.join(OUT_DIR, f"{name}_input.hex")
    exp_path = os.path.join(OUT_DIR, f"{name}_expected.hex")
    meta_path = os.path.join(OUT_DIR, f"{name}_meta.txt")

    write_hex(in_path, img)
    write_hex(exp_path, expected)
    with open(meta_path, "w") as f:
        f.write(f"name={name}\nsize={args.size}\npattern={args.pattern}\nseed={args.seed}\n")

    print(f"Wrote {in_path}")
    print(f"Wrote {exp_path}")
    print("\nInput image:")
    print(img)
    print("\nGolden sharpened output:")
    print(expected)


if __name__ == "__main__":
    main()
