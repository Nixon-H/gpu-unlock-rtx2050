# Experiments

Every tuning attempt made on this machine, with commands and results. All were
performed with the unlock active unless stated.

Reference point: sustained BF16 4096² GEMM = **24.5 TFLOPS** median.

---

## E1 — Does the unlock actually take effect?

**Method:** read the register state from the kernel log.

```
stage=gfw    plm=0xffffff8f ss0=0x10312022 ss1=0x3
pass=1/2     target=0x1fa7cc 0x4cb8f -> 0xfffff0ff
pass=2/2     target=0x823804 0x4cb8f -> 0xffffffff
stage=host   ss0=0x88888888 ss1=0x8
stage=flr    ss0=0x88888888 ss1=0x8 plm=0xffffffff
stage=handoff ret=0
gpu_unlock: unlocked
```

**Result:** SS0 went from `0x10312022` (override bit clear in every 4-bit field)
to `0x88888888` (bit 3 set, rate 0 = full in all eight fields); SS1 `0x3 → 0x8`.
Both survived the FLR.
**Conclusion:** the cap is removed at the hardware level. This is the primary
proof; benchmarks are secondary.

---

## E2 — Which dtype benefits?

**Method:** 4096² GEMM, 10 s each, same process.

| dtype | TFLOPS |
| --- | --- |
| FP16 | 13.3 |
| BF16 | 24.5 |
| TF32 | 10.5 |

**Conclusion:** BF16 is ~1.84× faster than FP16 in this stack. This is the
single largest software lever available — larger than every clock/fan tweak
combined.

---

## E3 — FP16 kernel variant

**Method:** toggle `torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction`.

| Setting | TFLOPS |
| --- | --- |
| ON | 13.4 |
| OFF | 13.3 |

**Conclusion:** no effect. FP16 stays at the locked ceiling regardless, which
points at cuBLAS choosing a different kernel rather than a hardware limitation.

---

## E4 — Clock locking at 2100 MHz

**Method:** `sudo nvidia-smi -lgc 2100`, then sustained BF16 4096² for 15 s.

| Metric | Dynamic (default) | Locked 2100 |
| --- | --- | --- |
| BF16 median | 24.5 | 24.8 (+1%) |
| BF16 best | 26.2 | 26.1 |
| Held clock | 1672–1687 | 1732–1755 |
| Idle clock | 210 MHz | **1740 MHz** |
| Idle power | 3.8–7 W | **14 W** |

**Conclusion:** +1% for 2× idle power. Reverted with `nvidia-smi -rgc`.
The 70 W cap means the card cannot hold 2100 anyway.

---

## E5 — Maximum fan speed

**Method:** ASUS WMI exposes `pwm1_enable` (cpu_fan) and `pwm2_enable`
(gpu_fan); `0` = full speed, `2` = automatic. Set both to 0, then sustained
BF16 for 15 s.

| Metric | Auto | Full fans |
| --- | --- | --- |
| Fan RPM (load) | 4400 | 4700–5000 |
| Temp (load) | 85–87 °C | 83–85 °C |
| BF16 median | 24.5 | 25.0 (+2%) |
| Idle noise | quiet | ~5000 RPM constant |

**Conclusion:** +2%, 2 °C, and permanent noise. Reverted to automatic.
Use `fan.sh max` only for long runs. Tool: `sudo sh fan.sh max|auto`.

---

## E6 — Raising the power limit

**Method:** `sudo nvidia-smi -pl 70`.

```
Changing power management limit is not supported in current scope
for GPU: 00000000:01:00.0.
```

**Observation:** default 55 W, max 70 W, and the card already draws 68–70 W
under load. **Conclusion:** TGP is firmware-locked; this is the real ceiling.

---

## E7 — Platform / thermal policy

| Control | Value | Writable |
| --- | --- | --- |
| `/sys/firmware/acpi/platform_profile` | `performance` | yes, already max |
| `asus-nb-wmi/throttle_thermal_policy` | `1` (overboost) | yes, already max |
| `nv_tgp` / `ppt_pl*` | not exposed on this model | — |

**Conclusion:** no additional headroom hidden in the vendor interfaces.

---

## E8 — Idle behaviour after tuning

After reverting the clock lock and fan override:

```
210 MHz, 405 MHz, 7.03 W, 74 °C
pwm1=2 pwm2=2, cpu_fan=4700 gpu_fan=4700
```

**Conclusion:** machine returned to the quiet baseline; no tuning left behind.

---

## Summary of levers

| Lever | Gain | Cost | Kept? |
| --- | --- | --- | --- |
| Unlock (the point) | ~1.8× BF16 | — | yes |
| BF16 instead of FP16 | +84% | none | yes (workload choice) |
| Full fans | +2% | constant 5000 RPM | no (toggle available) |
| Clock lock 2100 | +1% | 4× idle power | no |
| Power limit | 0 | firmware-locked | — |
