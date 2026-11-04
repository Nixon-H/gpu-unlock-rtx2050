#!/bin/sh
# Install the GA107-patched gpu-unlock (RTX 2050, 10de:25ad) on Debian 13.
# Run as root: sudo ./install-rtx2050.sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/src"
ASSETS="$HERE/assets"
VERSION=$(cat "$SRC/VERSION")
NV=610.43.03
NAME=gpu-unlock
DKMSDIR="/usr/src/$NAME-$VERSION"
FWDIR="/usr/lib/firmware/gpu-unlock/$NV"
PCI="0000:01:00.0"

echo "== hardware check"
lspci -nn | grep -i '10de:25ad' || {
	echo "ERROR: no NVIDIA 10de:25ad (RTX 2050) found; refusing to install" >&2
	exit 1
}

if [ ! -f "$ASSETS/gsp_ga10x.bin" ]; then
	echo "== firmware assets missing; generating them (downloads ~354 MB from NVIDIA)"
	command -v zstd >/dev/null 2>&1 || { echo "ERROR: zstd is required" >&2; exit 1; }
	make -C "$SRC" inputs firmware \
		CACHE="$HERE/cache" INPUTS="$HERE/cache/inputs" ASSETS="$ASSETS"
fi
[ -f "$ASSETS/gsp_ga10x.bin" ] || { echo "ERROR: firmware asset generation failed" >&2; exit 1; }

echo "== module source -> $DKMSDIR"
install -d "$DKMSDIR"
install -m 0644 "$SRC"/kernel/gpu_unlock/*.c "$SRC"/kernel/gpu_unlock/*.h "$DKMSDIR"/
install -m 0644 "$SRC"/kernel/gpu_unlock/Kbuild "$SRC"/kernel/gpu_unlock/Makefile \
	"$SRC"/kernel/gpu_unlock/dkms.conf "$DKMSDIR"/

if dkms status 2>/dev/null | grep -q "^$NAME/$VERSION"; then
	echo "== removing previous $NAME/$VERSION"
fi
dkms remove -m "$NAME" -v "$VERSION" --all >/dev/null 2>&1 || true

echo "== dkms add/build/install"
dkms add "$DKMSDIR"
dkms build -m "$NAME" -v "$VERSION"
dkms install -m "$NAME" -v "$VERSION" --force

echo "== firmware -> $FWDIR"
install -d "$FWDIR"
install -m 0644 "$ASSETS"/*.bin "$FWDIR"/
install -Dm644 "$ASSETS/NVIDIA-LICENSE" /usr/share/licenses/gpu-unlock-firmware/NVIDIA-LICENSE
install -Dm644 "$SRC/firmware/NOTICE.md" /usr/share/licenses/gpu-unlock-firmware/NOTICE.md

echo "== initramfs hooks"
install -Dm644 "$SRC/packaging/boot/initramfs-tools.conf" \
	/usr/share/initramfs-tools/modules.d/gpu-unlock.conf
install -Dm755 "$SRC/packaging/boot/initramfs-tools-init-top" \
	/usr/share/initramfs-tools/scripts/init-top/gpu-unlock
update-initramfs -u -k all

echo "== verifying the initramfs before you reboot"
INITRD="/boot/initrd.img-$(uname -r)"
if command -v lsinitramfs >/dev/null 2>&1 && [ -f "$INITRD" ]; then
	lsinitramfs "$INITRD" | grep -q 'gpu_unlock\.ko' || {
		echo "ERROR: gpu_unlock.ko is missing from $INITRD" >&2
		echo "Do not reboot expecting an unlock; the module would not run." >&2
		exit 1
	}
	lsinitramfs "$INITRD" | grep -q 'gpu-unlock/610.43.03/gsp_ga10x.bin' || {
		echo "ERROR: the unlock firmware is missing from $INITRD" >&2
		exit 1
	}
	echo "ok: gpu_unlock.ko and gsp_ga10x.bin are both in the initramfs"
else
	echo "skip: lsinitramfs or $INITRD not available, check manually"
fi
dkms status | grep "^$NAME/$VERSION" || {
	echo "ERROR: dkms does not report $NAME/$VERSION as installed" >&2
	exit 1
}

echo "== kernel command line"
python3 - "$PCI" <<'PY'
import pathlib, re, shutil, sys
pci = sys.argv[1]
p = pathlib.Path("/etc/default/grub")
text = p.read_text()
if "gpu_unlock.targets=" in text:
    print("gpu_unlock.targets already configured; leaving /etc/default/grub alone")
else:
    shutil.copy2(p, str(p) + ".gpu-unlock.bak")
    text, n = re.subn(
        r'^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"',
        lambda m: m.group(1) + " gpu_unlock.targets=" + pci + '"',
        text, count=1, flags=re.M)
    if not n:
        sys.exit("ERROR: GRUB_CMDLINE_LINUX_DEFAULT not found in /etc/default/grub")
    p.write_text(text)
    print("backup: /etc/default/grub.gpu-unlock.bak")
    print("added:  gpu_unlock.targets=" + pci)
PY
update-grub

cat <<EOF

== installed
Module:   $NAME/$VERSION via DKMS ($(dkms status | grep "^$NAME/$VERSION"))
Firmware: $FWDIR
Cmdline:  gpu_unlock.targets=$PCI

Next: run the baseline benchmark BEFORE rebooting (still capped):
  python3 bench-tensor.py --label before

Then reboot and check:
  journalctl -k -b | grep gpu_unlock
  sh verify-unlock.sh
  python3 bench-tensor.py --label after
EOF
