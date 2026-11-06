#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-dc7051-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-dc7051-nvram.XXXXXX)
log=$(mktemp -t vt340-dc7051-timing.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" -video none -sound none -nothrottle \
	-seconds_to_run 20 -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/dc7051-sync-trace.lua \
	>"$log" 2>&1

# The first screen callback precedes the first timing event.  Every subsequent
# visible frame must correspond to exactly one driver-local DC7051 frame event.
test "$(rg -c 'event=screen_frame .*device_delta=0$' "$log")" -eq 1
if rg 'event=screen_frame .*device_delta=' "$log" | rg -qv 'device_delta=(0|1)$'; then
	echo "unexpected DC7051-to-screen frame delta" >&2
	exit 1
fi
rg -q 'event=summary .*screen_frame=1197 dc7051_frame=1198 .*frames_seen=1198' "$log"

echo "VT340 driver-local DC7051 timing integration passed"
