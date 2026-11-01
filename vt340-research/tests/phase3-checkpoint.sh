#!/bin/sh
set -eu

binary=${1:-./vt340}
log=$(mktemp -t vt340-phase3-checkpoint.XXXXXX)
trap 'rm -f "$log"' EXIT HUP INT TERM

vt340-research/tests/smoke.sh "$binary"

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 15 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase3-lowrom-regression.lua \
	>"$log" 2>&1

rg -q 'PHASE3_LOWROM_PASS uart=1 reset=1 .*bad_wait=0 .*result=1 operational=1' "$log"
echo "VT340 Phase 3 checkpoint passed"
