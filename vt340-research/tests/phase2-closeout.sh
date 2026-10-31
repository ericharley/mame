#!/bin/sh
set -eu

binary=${1:-./vt340}
normal_log=$(mktemp -t vt340-phase2-normal.XXXXXX)
ring_log=$(mktemp -t vt340-phase2-ring.XXXXXX)
trap 'rm -f "$normal_log" "$ring_log"' EXIT HUP INT TERM

vt340-research/tests/smoke.sh "$binary"

if rg -n 'PHASE2|0x41f7|0xdc02' src/mame/dec/vt340.cpp; then
	echo "Diagnostic Phase 2 trigger found in the production driver" >&2
	exit 1
fi

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 15 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/wait-to-ok/phase2-normal-regression.lua \
	>"$normal_log" 2>&1
rg -q 'PHASE2_NORMAL_PASS wait=1 b6=1 command32=0' "$normal_log"

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 15 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/wait-to-ok/phase2-ring-event.lua \
	>"$ring_log" 2>&1
rg -q 'PHASE2_RING_BRANCH .*pc=DC18 .*latch_before=01' "$ring_log"
rg -q 'PHASE2_RING_PASS .*pc=DC1D latch_after=00' "$ring_log"

echo "VT340 Phase 2 closeout passed"
