#!/usr/bin/env python3
"""Dense GEMM benchmark for the gpu-unlock before/after comparison.

Requires PyTorch with CUDA. Measures FP16/BF16 (FP32 accumulation, the path
the unlock affects) and FP32 (control, should not change).

  ./bench-tensor.py --label before     # run before rebooting
  sudo ./install-rtx2050.sh            # (if not already done)
  # reboot
  ./bench-tensor.py --label after

Results are appended to bench-results.json next to this script.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import statistics
import sys
import time

SIZES = (2048, 4096, 8192)
DTYPES = ("float16", "bfloat16", "float32")
WARMUP = 10
ITERS = 30


def median_seconds(torch, dtype, n: int) -> float:
    a = torch.randn((n, n), device="cuda", dtype=dtype)
    b = torch.randn((n, n), device="cuda", dtype=dtype)
    out = torch.empty((n, n), device="cuda", dtype=dtype)
    for _ in range(WARMUP):
        torch.mm(a, b, out=out)
    torch.cuda.synchronize()
    samples = []
    for _ in range(ITERS):
        start = time.perf_counter()
        torch.mm(a, b, out=out)
        torch.cuda.synchronize()
        samples.append(time.perf_counter() - start)
    return statistics.median(samples)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, help="e.g. before / after")
    parser.add_argument("--output", type=pathlib.Path,
                        default=pathlib.Path(__file__).with_name("bench-results.json"))
    args = parser.parse_args()

    try:
        import torch
    except ImportError:
        print("PyTorch is not installed. Minimal CUDA build:\n"
              "  python3 -m venv ~/.venvs/gpu-bench\n"
              "  ~/.venvs/gpu-bench/bin/pip install torch "
              "--index-url https://download.pytorch.org/whl/cu130\n"
              "  ~/.venvs/gpu-bench/bin/python " + __file__ + " --label " + args.label,
              file=sys.stderr)
        return 2

    if not torch.cuda.is_available():
        print("CUDA is not available to PyTorch", file=sys.stderr)
        return 2

    name = torch.cuda.get_device_name(0)
    print(f"{name} | torch {torch.__version__} | label={args.label}")
    print(f"{'dtype':10} {'size':>6} {'ms':>10} {'TFLOPS':>9}")

    results = {"label": args.label, "device": name,
               "torch": torch.__version__, "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
               "measurements": {}}
    for dtype_name in DTYPES:
        dtype = getattr(torch, dtype_name)
        results["measurements"][dtype_name] = {}
        for n in SIZES:
            seconds = median_seconds(torch, dtype, n)
            tflops = 2.0 * n ** 3 / seconds / 1e12
            results["measurements"][dtype_name][str(n)] = {
                "seconds": seconds, "tflops": tflops}
            print(f"{dtype_name:10} {n:6d} {seconds * 1e3:10.2f} {tflops:9.1f}")

    history = []
    if args.output.exists():
        try:
            history = json.loads(args.output.read_text())
        except json.JSONDecodeError:
            history = []
    history.append(results)
    args.output.write_text(json.dumps(history, indent=2) + "\n")
    print(f"\nappended to {args.output}")

    before = next((h for h in history if h["label"] == "before"), None)
    after = next((h for h in history if h["label"] == "after"), None)
    if before and after:
        print("\nbefore -> after:")
        for dtype_name in ("float16", "bfloat16", "float32"):
            for n in SIZES:
                b = before["measurements"].get(dtype_name, {}).get(str(n))
                a = after["measurements"].get(dtype_name, {}).get(str(n))
                if b and a:
                    print(f"  {dtype_name:10} {n:6d}  "
                          f"{b['tflops']:7.1f} -> {a['tflops']:7.1f} TFLOPS "
                          f"({(a['tflops'] / b['tflops'] - 1) * 100:+.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
