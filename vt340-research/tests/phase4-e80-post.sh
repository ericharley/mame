#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
log=$(mktemp -t vt340-phase4-e80.XXXXXX)
nvram=$(mktemp -d -t vt340-phase4-e80-nvram.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -f "$log"; rm -rf "$nvram"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -nvram_directory "$nvram" -video none -sound none -nothrottle \
	-seconds_to_run 126 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-cpu1-bit0-diagnostic.lua \
	>"$log" 2>&1

rg -q 'event=first_stage1_sum .*R3=00' "$log"
rg -q 'event=checksum_call_2 result=00' "$log"
rg -q 'event=checksum_return .*R3=00' "$log"
rg -q 'event=command32_submit result=00' "$log"
rg -q 'PHASE4_BIT0_PASS reads=574' "$log"

echo "VT340 Phase 4 E80 POST regression passed"
