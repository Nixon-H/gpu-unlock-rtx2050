#!/bin/sh
# Turn the boot-time unlock OFF without uninstalling anything.
# The module stays in the initramfs but does nothing without the kernel argument.
# Run as root, then reboot.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

python3 - <<'PY'
import pathlib, re
p = pathlib.Path("/etc/default/grub")
text = p.read_text()
new = re.sub(r' gpu_unlock\.(targets|resume)=[^ "]*', '', text)
if new != text:
    p.write_text(new)
    print("removed gpu_unlock.* from GRUB_CMDLINE_LINUX_DEFAULT")
else:
    print("no gpu_unlock.* present; nothing to do")
PY

update-grub
echo "Unlock disabled. Reboot for it to take effect (module stays installed, inert)."
