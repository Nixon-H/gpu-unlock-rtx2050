#!/bin/sh
# Turn the boot-time unlock back ON after disable-unlock.sh.
# Run as root, then reboot.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

PCI="${1:-0000:01:00.0}"
python3 - "$PCI" <<'PY'
import pathlib, re, sys
pci = sys.argv[1]
p = pathlib.Path("/etc/default/grub")
text = p.read_text()
if "gpu_unlock.targets=" in text:
    print("gpu_unlock.targets already present; leaving /etc/default/grub alone")
else:
    text, n = re.subn(
        r'^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"',
        lambda m: m.group(1) + " gpu_unlock.targets=" + pci + '"',
        text, count=1, flags=re.M)
    if not n:
        sys.exit("ERROR: GRUB_CMDLINE_LINUX_DEFAULT not found")
    p.write_text(text)
    print("added gpu_unlock.targets=" + pci)
PY

update-grub
echo "Unlock enabled for $PCI. Reboot to apply."
