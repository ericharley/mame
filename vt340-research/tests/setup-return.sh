#!/bin/sh
set -eu

binary=${1:-./vt340}
log=$(mktemp -t vt340-setup-return.XXXXXX)
json=$(mktemp -t vt340-setup-return.XXXXXX)
trap 'rm -f "$log" "$json"' EXIT HUP INT TERM

VT340_SETUP_RETURN_SIMPLE=1 "$binary" vt340 -rompath roms \
	-video none -sound none -nothrottle -seconds_to_run 164 \
	-autoboot_delay 0 \
	-autoboot_script vt340-research/traces/setup-return-trace.lua \
	>"$log" 2>&1

rg '^VT340_SETUP_RETURN_JSON ' "$log" | sed 's/^VT340_SETUP_RETURN_JSON //' >"$json"

before=$(jq -r 'select(.event == "capture" and .target == 135) | .hash' "$json")
after=$(jq -r 'select(.event == "capture" and .target == 164) | .hash' "$json")
test "$before" = "2185572B"
test "$after" = "$before"
rg -q 'VT340_SETUP_RETURN_MODEL .*address=800D data=00' "$log"

echo "VT340 native Set-Up return regression passed"
