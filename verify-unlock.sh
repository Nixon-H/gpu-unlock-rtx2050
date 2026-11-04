#!/bin/sh
# Read-only check of the unlock after a boot.
set -u

echo "== kernel message"
if command -v journalctl >/dev/null 2>&1; then
	journalctl -k -b 2>/dev/null | grep -i gpu_unlock || echo "no gpu_unlock lines in this boot"
else
	dmesg 2>/dev/null | grep -i gpu_unlock || echo "no gpu_unlock lines (try sudo dmesg)"
fi

echo
echo "== module state"
if [ -d /sys/module/gpu_unlock ]; then
	echo "loaded:   yes"
	echo "targets:  $(cat /sys/module/gpu_unlock/parameters/targets 2>/dev/null)"
	echo "resume:   $(cat /sys/module/gpu_unlock/parameters/resume 2>/dev/null)"
else
	echo "loaded:   no"
fi

echo
echo "== device"
lspci -nnk -s 0000:01:00.0

echo
echo "== dkms"
dkms status 2>/dev/null | grep gpu-unlock || echo "not registered with dkms"

echo
echo "Interpretation:"
echo "  'gpu_unlock: unlocked' in the log + targets set  -> selectors were written"
echo "  'unlock failed (-19)'                            -> PMC_BOOT_0 chip ID mismatch (wrong recipe), nothing written"
echo "  'already initialised since power on'             -> nvidia bound first; module too late in the initramfs"
