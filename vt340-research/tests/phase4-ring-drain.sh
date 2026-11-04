#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
log=$(mktemp -t vt340-phase4-ring-drain.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -f "$log"' EXIT HUP INT TERM

if rg -n 'pc == 0x0047.*|data &= ~0x01' src/mame/dec/vt340.cpp; then
	echo "PC-qualified DC323 status inversion found in production driver" >&2
	exit 1
fi

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 125 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-cpu2-ring-drain.lua \
	>"$log" 2>&1

rg -q 'event=first_ring_drained .*producer=17 consumer=17' "$log"
rg -q 'event=startup_restore .*producer=54 consumer=54' "$log"
rg -q 'event=command32_submit' "$log"
rg -q 'event=command32_handler' "$log"
rg -q 'event=command32_ring_poll .*producer=66 consumer=66' "$log"
rg -q 'PHASE4_RING_DRAIN_PASS producer_writes=102 consumer_writes=102 ack_fe=[1-9][0-9]* ack_fd=[1-9][0-9]* ack_other=0' "$log"

echo "VT340 Phase 4 CPU2 ring-drain regression passed"
