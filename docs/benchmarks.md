# Benchmarks

All numbers measured on the machine described in the main README, with the
unlock active (`gpu_unlock: unlocked`), unless stated otherwise.

## Environment

| Item | Value |
| --- | --- |
| GPU | RTX 2050 Laptop, GA107, 16 SMs, 4 GB |
| Driver | 615.71.10 (open kernel modules) |
| Kernel | 7.2.11+deb13-amd64 |
| PyTorch | 2.15.0+cu132 |
| Benchmark | `bench-tensor.py`, dense `torch.mm`, 30 iterations, median |
| Power mode | ACPI `performance`, ASUS thermal policy `1` |
| Cooling | stock, auto fan |

`bench-tensor.py` warms up 10 iterations before timing, synchronizes every
iteration, and records the median. TFLOPS = `2·N³ / t`.

## Locked ceiling (computed, not measured)

GA10x consumer silicon issues the FP32-accumulate tensor path at
512 FLOP/clk/SM. With 16 SMs:

| Clock | Locked ceiling | Unlocked ceiling |
| --- | --- | --- |
| 1.6 GHz | 13.1 TFLOPS | 26.2 |
| 1.69 GHz | 13.8 TFLOPS | 27.7 |
| 1.8 GHz | 14.7 TFLOPS | 29.5 |
| 2.1 GHz (max) | 17.2 TFLOPS | 34.4 |

These are hard ceilings: a still-capped card cannot exceed them at the same
clock. This is why the sustained 24.5 TFLOPS below is evidence of the unlock
on its own, independent of any before/after run.

There is no separate "before" run in this repo: the card could not be benchmarked
locked without a reboot, and the register readback plus the ceiling argument
cover the same ground. If you want a true A/B, use `disable-unlock.sh` + reboot,
measure, then `enable-unlock.sh` + reboot.

## Size scaling (single run per point)

| dtype | 2048² | 4096² | 8192² |
| --- | --- | --- | --- |
| FP16 | 17.3 | 13.2 | 12.5 |
| BF16 | 24.6 | 25.5 | 13.4 |
| FP32 | 4.1 | 4.0 | 4.2 |

TFLOPS. The 8192 points are memory/bandwidth bound on a 64-bit 4 GB card;
FP32 is CUDA-core bound and unchanged by the unlock.

## Sustained (4096², 10–20 s per dtype)

| dtype | median | best | iterations |
| --- | --- | --- | --- |
| BF16 | **24.5** | 26.2 | 3577 (20 s) |
| TF32 | 10.5 | 11.7 | 10 s |
| FP16 | 13.3 | 17.4 | 10 s |
| FP32 | 4.1 | — | 30 |

BF16 reaches ~90% of the unlocked ceiling at the clock the card actually holds
(1.69 GHz → 27.7 TFLOPS). FP16 stays at the locked ceiling in this PyTorch
build — a cuBLAS kernel-selection difference, not a partial unlock (the
register readback shows every field at full rate).

## Thermals and clocks under load

Sampled once per second while running sustained BF16 GEMM:

| Metric | Idle | Sustained load |
| --- | --- | --- |
| SM clock | 210 MHz | 1672–1755 MHz |
| Memory clock | 405 MHz | **7001 MHz (max)** |
| Power | 4–7 W | **68–70 W** |
| Temperature | 65–74 °C | **83–87 °C** |
| GPU util | 0 % | 96–100 % |
| Fan | 4300–4700 RPM | 4400–4700 RPM |

Throttle counters after the test session: SW thermal slowdown 10.5 s, SW power
capping 4.2 s, HW thermal/power brake 0 s. The card is power-limited, not
thermally braked.

## Real-world expectation

Sustained BF16 dense GEMM improves from the ~13.8 TFLOPS locked ceiling to
24.5 TFLOPS ≈ **1.8×**. Workload speedups will be lower where the model is
memory-bound (token decode), and higher where it is prefill/GEMM-bound. On a
4 GB, 70 W laptop part, expect **+40–70%** on prefill-heavy work and **no
change** on decode-dominated work.
