#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-setup-return-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-setup-return-nvram.XXXXXX)
log=$(mktemp -t vt340-setup-return.XXXXXX)
json=$(mktemp -t vt340-setup-return.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; vt340_artifact_copy "$json" "events.jsonl"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log" "$json"' EXIT HUP INT TERM

VT340_SETUP_RETURN_SIMPLE=1 "$binary" vt340 -rompath roms \
	-cfg_directory "$config_dir" -nvram_directory "$nvram_dir" \
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
