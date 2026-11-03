#!/bin/sh
set -eu

binary=${1:-./vt340}
slots=$(mktemp -t vt340-serial-slots.XXXXXX)
devices=$(mktemp -t vt340-serial-devices.XXXXXX)
log=$(mktemp -t vt340-serial-post.XXXXXX)
trap 'rm -f "$slots" "$devices" "$log"' EXIT HUP INT TERM

"$binary" -listslots vt340 >"$slots"
rg -q 'comm1' "$slots"
rg -q 'comm2' "$slots"
test "$(rg -c 'Pseudo Terminal' "$slots")" -eq 2

"$binary" vt340 -comm1 pty -comm2 pty -listdevices >"$devices"
test "$(rg -c 'Pseudo Terminal' "$devices")" -eq 2

# Attaching both host ports must not alter the native serial diagnostics or
# the zero POST result.
"$binary" vt340 -rompath roms -comm1 pty -comm2 pty \
	-video none -sound none -nothrottle -seconds_to_run 126 \
	-debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-cpu1-bit0-diagnostic.lua \
	>"$log" 2>&1

rg -q 'event=command32_submit result=00' "$log"
rg -q 'PHASE4_BIT0_PASS reads=574' "$log"

echo "VT340 external serial connector regression passed"
