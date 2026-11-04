#!/bin/sh
# Toggle ASUS WMI fan mode. Needs root: sudo sh fan.sh auto|max
#   max  -> pwm_enable=0 (full speed, ~5000 RPM, loud)
#   auto -> pwm_enable=2 (EC curve, quiet)
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }
H=/sys/devices/platform/asus-nb-wmi/hwmon/hwmon5

case "${1:-auto}" in
max)  v=0 ;;
auto) v=2 ;;
*)    echo "usage: $0 auto|max" >&2; exit 2 ;;
esac

echo "$v" > "$H/pwm1_enable"   # cpu_fan
echo "$v" > "$H/pwm2_enable"   # gpu_fan
echo "pwm1=$(cat "$H/pwm1_enable") pwm2=$(cat "$H/pwm2_enable") cpu_fan=$(cat "$H/fan1_input") gpu_fan=$(cat "$H/fan2_input")"
