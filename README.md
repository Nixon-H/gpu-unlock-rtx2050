# gpu-unlock for RTX 2050 (GA107 · `10de:25ad`)

A working port of [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) to the
**NVIDIA GeForce RTX 2050 Laptop GPU**, with a verified activation/deactivation/
removal workflow and measured benchmarks (including thermals).

The RTX 2050 is GA107 silicon. Upstream supports GA102/GA103/GA104/GA106 and
experimental Turing/Ada families, but the device table contains **no GA107 family
and no `0x25ad`**, so the stock module refuses the card. This repo adds exactly
that, nothing else in the unlock path.

**Verified on real hardware** (see [docs/benchmarks.md](docs/benchmarks.md) and
[docs/experiments.md](docs/experiments.md)):

```
stage=claim  device=0x25ad family=GA102/GA103/GA104/GA106/GA107
before:      plm=0xffffff8f  ss0=0x10312022  ss1=0x3
pass 1:      0x1fa7cc  0x4cb8f -> 0xfffff0ff
pass 2:      0x823804  0x4cb8f -> 0xffffffff
after:       ss0=0x88888888  ss1=0x8
post-FLR:    ss0=0x88888888  ss1=0x8
gpu_unlock: unlocked
```

---

## Contents

- [What it does](#what-it-does)
- [Tested configuration](#tested-configuration)
- [Install (clone and run)](#install-clone-and-run)
- [Activate](#activate)
- [Verify](#verify)
- [Deactivate](#deactivate)
- [Uninstall / delete](#uninstall--delete)
- [Benchmarks](#benchmarks)
- [Limits on this laptop](#limits-on-this-laptop)
- [How it works](#how-it-works)
- [Safety and failure modes](#safety-and-failure-modes)
- [Troubleshooting](#troubleshooting)
- [Licensing and credits](#licensing-and-credits)

---

## What it does

NVIDIA ships GeForce cards with the FP16/BF16/TF32 tensor path that accumulates
into FP32 limited to roughly half the issue rate of the same silicon sold as a
professional card. `gpu-unlock` runs a signed SEC2 booter with a patched
signature before the NVIDIA driver binds, uses the resulting ROP chain to open
two permission registers, writes the speed selectors, and resets the GPU (FLR)
so the stock driver starts clean on an unlocked card.

- No BIOS/VBIOS flash.
- No patched NVIDIA driver.
- No voltage, clock or power-limit modification.
- Survives driver updates (DKMS rebuilds the module).
- Survives suspend/resume (the module re-unlocks before `nvidia` resumes).

Measured effect on this RTX 2050: **BF16 dense GEMM 24.5 TFLOPS sustained**,
against a hard locked ceiling of ~13.8 TFLOPS at the same clock.

---

## Tested configuration

| Component | Version |
| --- | --- |
| GPU | NVIDIA GeForce RTX 2050 Laptop, GA107, `10de:25ad`, 4 GB |
| Host | ASUS laptop, Intel TigerLake-H iGPU + dGPU |
| OS | Debian 13 (trixie) |
| Kernel | `7.2.11+deb13-amd64` |
| NVIDIA driver | 615.71.10 (open kernel modules) |
| Secure Boot | disabled |
| Firmware used by unlock | pinned 610.43.03 (generated locally) |
| Benchmark stack | PyTorch 2.15.0+cu132 |

Other GA107 boards (RTX 3050 mobile/desktop) are already reported working
upstream in PRs #69, #96, #104, #113, #222, #231, #245. This repo's only device
addition is `0x25ad`.

---

## Install (clone and run)

Requirements: Linux, root, kernel headers for the running kernel, `dkms`,
`python3`, `zstd`, ~1 GB free disk for the NVIDIA inputs.

```sh
git clone https://github.com/Nixon-H/gpu-unlock-rtx2050.git
cd gpu-unlock-rtx2050
sudo sh install-rtx2050.sh
```

On first run the installer downloads the pinned NVIDIA 610.43.03 artifacts
(~354 MB) and extracts the firmware. **No NVIDIA firmware is stored in this
repository**; it is generated locally from NVIDIA's own package.

What the installer does:

1. Checks `lspci` for `10de:25ad` and refuses to continue otherwise.
2. Installs the module source to `/usr/src/gpu-unlock-2.0.0`.
3. `dkms add` → `build` → `install` (signed with the local DKMS MOK key).
4. Installs 16 firmware files to `/usr/lib/firmware/gpu-unlock/610.43.03`.
5. Installs the initramfs-tools hook so the module runs before `nvidia`.
6. Rebuilds the initramfs and **verifies `gpu_unlock.ko` and
   `gsp_ga10x.bin` are actually inside it** — aborting if not.
7. Adds `gpu_unlock.targets=0000:01:00.0` to `GRUB_CMDLINE_LINUX_DEFAULT`
   (backup at `/etc/default/grub.gpu-unlock.bak`) and runs `update-grub`.

Expected final line before rebooting:

```
ok: gpu_unlock.ko and gsp_ga10x.bin are both in the initramfs
```

> If you use a different PCI address, edit `PCI=` in the installer or pass the
> address to `enable-unlock.sh`. Find it with `lspci -nn | grep 10de:25ad`.

---

## Activate

The unlock runs **at boot**, before the NVIDIA driver binds. There is no runtime
command — the kernel argument is the switch.

```sh
sudo reboot
```

`gpu_unlock.targets=...` is already set by the installer, so the next boot
unlocks the card. To re-enable after `disable-unlock.sh`:

```sh
sudo sh enable-unlock.sh
sudo reboot
```

One-off boot without the unlock: at the GRUB menu press `e`, delete the
`gpu_unlock.targets=...` token from the `linux` line, boot.

---

## Verify

```sh
sudo journalctl -k -b -g gpu_unlock
# or: sudo dmesg | grep gpu_unlock
```

Success:

```
gpu_unlock: stage=host  ss0=0x88888888 ss1=0x8 plm_feat=0xffffffff
gpu_unlock: stage=flr   ss0=0x88888888 ss1=0x8
gpu_unlock: unlocked
```

Note: on Debian, an unprivileged `journalctl -k` shows nothing (kernel log
restricted); use `sudo`.

`sh verify-unlock.sh` prints the same information without needing root for the
non-journal parts.

---

## Deactivate

Keeps everything installed but stops unlocking (module loads and returns
immediately).

```sh
sudo sh disable-unlock.sh
sudo reboot
```

Re-activate later with `enable-unlock.sh` + reboot. No reinstall needed.

---

## Uninstall / delete

Removes the module, firmware, initramfs hooks and the kernel argument:

```sh
sudo sh uninstall-rtx2050.sh
sudo reboot
```

That script also removes `/usr/src/gpu-unlock-2.0.0`, the DKMS registration,
`/usr/lib/firmware/gpu-unlock/610.43.03`, the initramfs drop-ins, and restores
`gpu_unlock.*` out of `/etc/default/grub`.

Then delete the checkout:

```sh
cd ..
rm -rf gpu-unlock-2050
```

Local caches you may also want to remove: `cache/` (354 MB), `assets/`,
and `~/.venvs/gpu-bench` if you used the benchmark.

---

## Benchmarks

Full method and every run: [docs/benchmarks.md](docs/benchmarks.md).
Experiments (clock lock, fan control, dtype paths): [docs/experiments.md](docs/experiments.md).

Sustained 4096×4096 GEMM, PyTorch 2.15, unlocked:

| dtype | TFLOPS | note |
| --- | --- | --- |
| BF16 | **24.5** (best 26.2) | ~90% of the unlocked peak at the achieved clock |
| TF32 | 10.5 | ~1.5× the locked ceiling |
| FP16 | 13.3 | no gain in this stack (kernel selection, not the unlock) |
| FP32 (CUDA) | 4.1 | unchanged, as expected |

Locked ceiling at the same clock (16 SMs × 512 FLOP/clk): **~13.8 TFLOPS**.
The card measured **24.5** — a capped card cannot do that, which is the point.

Thermals under sustained tensor load: **68–70 W, 83–87 °C, 1672–1755 MHz,
memory at 7001 MHz**. Idle: 210 MHz, ~4–7 W.

---

## Limits on this laptop

| Limit | Value | Adjustable? |
| --- | --- | --- |
| TGP | 70 W hard max (default 55 W) | **No** — `nvidia-smi -pl` returns "not supported in current scope" |
| SM clock | 2100 MHz max | Dynamic boost only; power-capped to ~1700 under load |
| Memory clock | 7001 MHz | Fixed at max under load |
| ACPI platform profile | `performance` | Already max |
| ASUS thermal policy | `1` (overboost) | Already max |
| Fan | `pwm1_enable`/`pwm2_enable` (0=full, 2=auto) | Yes, see `fan.sh` — worth ~2% |

Because the card is power-limited rather than clock- or thermal-limited,
software tuning yields very little: clock locking gave +1% (and raised idle
power 4×), full fans gave +2%. The real lever is **using BF16 rather than FP16**
in this PyTorch build (+84% at 4096).

---

## How it works

1. **Firmware bootstrap.** The module maps BAR0, reads `PMC_BOOT_0`, and
   requires chip ID `0x177` (`(value >> 20) & 0x1ff`). Any other chip aborts
   with `-ENODEV` **before a single write**.
2. **SEC2 booter.** It uploads the signed SEC2 Booter from the pinned GSP
   package with a patched signature section, yielding a controlled
   `MEMORY[address] = value` primitive inside the boot firmware.
3. **Permission registers.** Two writes open the FEAT aperture:
   - `0x1fa7cc` (`WPR_CFG_PLM`) `0x4cb8f → 0xfffff0ff`
   - `0x823804` (`FEAT_PLM`) `0x4cb8f → 0xffffffff`
4. **Speed selectors** (host writes):
   - `0x82381c` (`FEAT_OVR_SM_SPD` / SS0) `→ 0x88888888` (eight 4-bit fields)
   - `0x823820` (`FEAT_OVR_SM_SPD_1` / SS1) `→ 0x8` (IMLA4)
   Each field uses bit 3 as "override enable" and bits 2:0 as the rate
   (0 = full, 1 = half, 2 = quarter, 3 = eighth).
5. **FLR.** A function-level reset clears the GSP state; the selectors persist.
6. **Handoff.** The unmodified NVIDIA driver binds to a clean GPU.

The recipe patch is three lines:

```c
#define GA107(id) { id, 0x177, &ga10x }
...
GA107(0x25ad),
```

---

## Safety and failure modes

What is **not** touched: voltage, power limits, clock ceilings, fan firmware,
VBIOS. Only permission bits and rate-selector registers.

Failure modes observed or possible:

| Symptom | Cause | Recovery |
| --- | --- | --- |
| `unlock failed (-19)` | `PMC_BOOT_0` chip ID ≠ `0x177` | Nothing was written. Remove the arg or leave it |
| `already initialised since power on (WPR2 enabled)` | module ran after `nvidia` bound | check initramfs ordering; cold boot |
| Blank screen / hang at boot | firmware step failed on this board | GRUB `e`, delete `gpu_unlock.targets=...`, boot, then uninstall |
| No `gpu_unlock` lines at all | module not in initramfs or arg not applied | check `lsinitramfs` and `/proc/cmdline` |

No permanent hardware damage has been reported for this technique, and the
writes are confined to rate-control registers. That said, this is an
undocumented firmware path on a model with no public prior validation — treat
it as experimental, and keep the GRUB rollback in mind.

Thermals are unchanged by the unlock itself; the extra compute can raise
sustained power draw, but the laptop's own power and thermal throttling remain
in control.

---

## Troubleshooting

**`journalctl` prints nothing.** Kernel log is root-only on Debian:
`sudo journalctl -k -b -g gpu_unlock`.

**Module not in initramfs.** `lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'gpu_unlock|gsp_ga10x'`
(needs root). Re-run the installer if missing.

**No unlock but the module loaded.** Check `/proc/cmdline` contains
`gpu_unlock.targets=0000:01:00.0`.

**Secure Boot.** The module is unsigned by the distro; with Secure Boot on you
must enrol the DKMS MOK key (`mokutil --import /var/lib/dkms/mok.pub`) or it
will not load. This machine has Secure Boot disabled.

**Different PCI address.** `lspci -nn | grep 10de:25ad`, then
`sudo sh enable-unlock.sh 0000:XX:00.0`.

---

## Licensing and credits

- Module source and this repo's scripts/docs: **GPL-2.0-only**, matching
  upstream.
- Unlock technique and recipes: [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock)
  (GPL-2.0), which builds on the cmpunlocker V67/PLM work (Petri Krohn,
  `amoghmunikote/cmpunlocker`, GPL-2.0) and the RTX 4090 register work by
  `elias-gaeros`.
- GA107 device-ID macro mirrors upstream PR #231.
- **NVIDIA firmware is not included.** The installer downloads NVIDIA's
  pinned 610.43.03 package and extracts it locally. Those binaries remain
  under the NVIDIA Driver License Agreement; see `src/firmware/NOTICE.md`.
  Do not redistribute them.
