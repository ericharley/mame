#!/bin/sh
set -eu

binary=${1:-./vt340}
log=$(mktemp -t vt340-setup-screen.XXXXXX)
json=$(mktemp -t vt340-setup-screen.XXXXXX)
trap 'rm -f "$log" "$json"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 143 -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/setup-screen-trace.lua \
	>"$log" 2>&1

rg '^VT340_SETUP_JSON ' "$log" | sed 's/^VT340_SETUP_JSON //' >"$json"

test "$(jq -s '[.[] | select(.event == "setup_key" and .data == "58")] | length' "$json")" -eq 1
jq -e 'select(.event == "summary" and
	.setup_key == true and
	.initialization_ready == true and
	.fifo_ready == true and
	.visible_hash == "514C8F54" and
	.lit_pixels == 43231 and
	.barrier_4be5 == "00")' "$json" >/dev/null

echo "VT340 native Set-Up screen regression passed"
