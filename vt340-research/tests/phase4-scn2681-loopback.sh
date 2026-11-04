#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
log=$(mktemp -t vt340-phase4-scn2681.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -f "$log"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 126 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-cpu1-comm1-diagnostic.lua \
	>"$log" 2>&1

# The formerly failing 7-bit odd-parity frame must be received as 0x26 with
# RxRDY/TxRDY/TxEMT set and no parity, framing, or overrun error.
rg -q 'op=W pc=43EC address=F043 data=A6' "$log"
rg -q 'op=R pc=440D address=F041 data=0D' "$log"
rg -q 'op=R pc=4414 address=F043 data=26' "$log"
rg -q 'op=W pc=43EC address=F04B data=A6' "$log"
rg -q 'op=R pc=440D address=F049 data=0D' "$log"
rg -q 'op=R pc=4414 address=F04B data=26' "$log"

if rg -q 'event=(failure_classify|bit1_set|bit5_set)' "$log"; then
	echo "SCN2681 local-loopback firmware failure path was taken" >&2
	exit 1
fi

test "$(rg -c 'event=mode_8f_result result=00' "$log")" -eq 2
rg -q 'event=command32_submit result=00' "$log"
rg -q 'PHASE4_COMM1_PASS .*result=00' "$log"

echo "VT340 Phase 4 SCN2681 local-loopback regression passed"
