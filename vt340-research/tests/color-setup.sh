#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
nvram=$(mktemp -d -t vt340-color-setup-nvram.XXXXXX)
log=$(mktemp -t vt340-color-setup.XXXXXX)
json=$(mktemp -t vt340-color-setup.XXXXXX)
trap 'rm -f "$log" "$json"; rm -rf "$nvram"' EXIT HUP INT TERM

"$binary" vt340 -rompath "$root/roms" -nvram_directory "$nvram" \
	-video none -sound none -nothrottle -seconds_to_run 282 \
	-autoboot_delay 0 \
	-autoboot_script "$root/vt340-research/traces/color-setup-trace.lua" \
	>"$log" 2>&1

rg '^VT340_COLOR_SETUP_JSON ' "$log" |
	sed 's/^VT340_COLOR_SETUP_JSON //' >"$json"

test "$(jq -s '[.[] | select(.event == "key" and .label == "select_color" and .code == "LK201_RIGHT")] | length' "$json")" -eq 1
jq -e 'select(.event == "capture" and
	.config_7b00 == "28" and
	.state_4c00 == "38")' "$json" >/dev/null

echo "VT340 native Color Map selection regression passed"
