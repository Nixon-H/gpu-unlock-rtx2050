#!/bin/sh
# Remove gpu-unlock and the RTX 2050 kernel command line change.
# Run as root: sudo ./uninstall-rtx2050.sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=$(cat "$HERE/src/VERSION")
NV=610.43.03
NAME=gpu-unlock

echo "== dkms remove"
if dkms status 2>/dev/null | grep -q "^$NAME/$VERSION"; then
	dkms remove -m "$NAME" -v "$VERSION" --all || true
fi
rm -rf "/usr/src/$NAME-$VERSION"

echo "== firmware and initramfs hooks"
rm -rf "/usr/lib/firmware/gpu-unlock/$NV"
rmdir "/usr/lib/firmware/gpu-unlock" 2>/dev/null || true
rm -f /usr/share/initramfs-tools/modules.d/gpu-unlock.conf
rm -f /usr/share/initramfs-tools/scripts/init-top/gpu-unlock
rm -rf /usr/share/licenses/gpu-unlock-firmware

echo "== kernel command line"
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("/etc/default/grub")
text = p.read_text()
new = re.sub(r' gpu_unlock\.(targets|resume)=[^ "]*', '', text)
if new != text:
    p.write_text(new)
    print("removed gpu_unlock.* from GRUB_CMDLINE_LINUX_DEFAULT")
else:
    print("no gpu_unlock.* in /etc/default/grub")
PY
update-grub
update-initramfs -u -k all

echo "== done; reboot to boot without the unlock"
