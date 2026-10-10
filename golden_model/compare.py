#!/usr/bin/env python3
"""
Compares the RTL simulation's output hex file against the golden expected
hex file. Reports pixel-exact mismatches with (row, col) coordinates.

Usage:
  python3 compare.py --expected vectors/t0_expected.hex --actual ../sim_out/t0_rtl_output.hex --size 8
"""
import argparse
import numpy as np


def load_hex(path, size):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals.append(int(line, 16))
    arr = np.array(vals, dtype=np.int64)
    expected_count = size * size
    if arr.size != expected_count:
        raise ValueError(
            f"{path}: expected {expected_count} pixels ({size}x{size}), "
            f"got {arr.size}. Did the RTL emit the wrong number of beats?"
        )
    return arr.reshape((size, size))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--expected", required=True)
    ap.add_argument("--actual", required=True)
    ap.add_argument("--size", type=int, required=True)
    args = ap.parse_args()

    expected = load_hex(args.expected, args.size)
    actual = load_hex(args.actual, args.size)

    mismatches = np.argwhere(expected != actual)
    total = expected.size

    print(f"Compared {total} pixels ({args.size}x{args.size})")
    if mismatches.size == 0:
        print("RESULT: PASS -- bit-exact match, 0 mismatches")
        return 0
    else:
        print(f"RESULT: FAIL -- {len(mismatches)} mismatch(es)")
        for (r, c) in mismatches:
            print(f"  (row={r}, col={c}): expected={expected[r,c]:3d}  actual={actual[r,c]:3d}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
