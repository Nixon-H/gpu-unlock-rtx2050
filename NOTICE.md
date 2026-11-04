# NOTICE

## What is in this repository

- Our changes: the GA107/`0x25ad` recipe entry, install/enable/disable/
  uninstall/verify scripts, `fan.sh`, `bench-tensor.py`, documentation.
- A copy of [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock)
  under `src/`, with the same patch applied. That project is GPL-2.0-only.
  Its own `README.md`, `firmware/NOTICE.md`, and `licenses/` are preserved
  under `src/`.

## What is NOT in this repository

**No NVIDIA firmware, and no NVIDIA installer archives.** The module needs
`gsp_ga10x.bin`, the SEC2 booter, the GSP boot images/descriptors and the
Falcon loader. Those are extracted at install time from NVIDIA's own pinned
610.43.03 packages, downloaded by the installer:

- `NVIDIA-kernel-module-source-610.43.03.tar.xz`
- `NVIDIA-Linux-x86_64-610.43.03-no-compat32.run`

Those binaries remain under the NVIDIA Driver License Agreement. They are
generated into `assets/` and installed to
`/usr/lib/firmware/gpu-unlock/610.43.03/` on the local machine only.
`assets/`, `assets.src/` and `cache/` are gitignored. Do not redistribute
extracted NVIDIA firmware.

## License

This repository's code and documentation: **GPL-2.0-only**, matching upstream.
See `LICENSE`.

## Credits

- Unlock technique, payload recipes, module: Zagitta/gpu-unlock (GPL-2.0).
- V67/PLM technique: Petri Krohn and `amoghmunikote/cmpunlocker` (GPL-2.0).
- Register/loading geometry for Ada: `elias-gaeros` RTX 4090 work.
- GA107 device ID set for the RTX 3050 family: upstream PR #231; this repo
  adds only `0x25ad` (RTX 2050).
