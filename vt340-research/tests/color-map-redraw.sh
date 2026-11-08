#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/vt340-research/tests/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-color-redraw-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-color-redraw-nvram.XXXXXX)
log=$(mktemp -t vt340-color-redraw.XXXXXX)
json=$(mktemp -t vt340-color-redraw.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; vt340_artifact_copy "$json" "events.jsonl"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log" "$json"' EXIT HUP INT TERM

cp "$root/vt340-research/fixtures/fast-start.cfg" "$config_dir/vt340.cfg"

"$binary" vt340 -rompath "$root/roms" -cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" -video none -sound none -nothrottle \
	-seconds_to_run 39 -autoboot_delay 0 \
	-autoboot_script "$root/vt340-research/traces/color-map-live-diagnostic.lua" \
	>"$log" 2>&1

rg '^VT340_COLOR_MAP_JSON ' "$log" |
	sed 's/^VT340_COLOR_MAP_JSON //' >"$json"

jq -e 'select(.capture == 30 and .color0 == "FF000000" and .red0 == "FF000000" and .green0 == "FF000000")' "$json" >/dev/null
jq -e 'select(.capture == 32 and .color0 == "FFFFFFFF")' "$json" >/dev/null
jq -e 'select(.capture == 34 and .color0 == "FF000000" and .red0 == "FFFFFFFF")' "$json" >/dev/null
jq -e 'select(.capture == 36 and .red0 == "FF000000" and .red1 == "FFFFFFFF")' "$json" >/dev/null
jq -e 'select(.capture == 38 and .red1 == "FF000000" and .green0 == "FFFFFFFF")' "$json" >/dev/null

echo "VT340 Color Set-Up immediate redraw regression passed"
