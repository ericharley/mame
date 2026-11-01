#!/bin/sh
set -eu

binary=${1:-./vt340}
normal_log=$(mktemp -t vt340-phase2-normal.XXXXXX)
trap 'rm -f "$normal_log"' EXIT HUP INT TERM

vt340-research/tests/smoke.sh "$binary"

if rg -n 'PHASE2|0x41f7|0xdc02' src/mame/dec/vt340.cpp; then
	echo "Diagnostic Phase 2 trigger found in the production driver" >&2
	exit 1
fi

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 25 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/wait-to-ok/phase2-normal-regression.lua \
	>"$normal_log" 2>&1
rg -q 'PHASE2_NORMAL_PASS wait=1 request=1 result=1 ack_wait=1 command32=0' "$normal_log"

echo "VT340 Phase 2 normal-path closeout passed"
