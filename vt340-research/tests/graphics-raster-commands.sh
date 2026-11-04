#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-graphics-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-graphics-nvram.XXXXXX)
log=$(mktemp -t vt340-graphics-raster.XXXXXX)
json=$(mktemp -t vt340-graphics-raster.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; vt340_artifact_copy "$json" "events.jsonl"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log" "$json"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" -video none -sound none -nothrottle \
	-seconds_to_run 130 -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/graphics-command-trace.lua \
	>"$log" 2>&1

rg '^VT340_GFX_JSON ' "$log" | sed 's/^VT340_GFX_JSON //' >"$json"

# The clean boot has 4,596 rasterop-form commands.  Only the 35 documented
# normal-mode, zero-memory-source operations are added by this change.
test "$(jq -s '[.[] | select(.event == "command" and .operation == 2)] | length' "$json")" -eq 4596
test "$(jq -s '[.[] | select(.event == "command" and .operation == 2 and .mode == "0080" and .source1 == false and .source2 == false and .supported == true)] | length' "$json")" -eq 35
test "$(jq -s '[.[] | select(.event == "command" and .operation == 2 and .destination == true and .source2 == true)] | length' "$json")" -eq 0

# Five 800x20 clears and one 800x24 clear are the only late zero-source
# operations.  They execute but find their off-screen target bands empty.
test "$(jq -s '[.[] | select(.event == "command" and .time >= 115 and .operation == 2 and .source1 == false and .source2 == false)] | length' "$json")" -eq 6
test "$(jq -s '[.[] | select(.event == "raster_result" and (.parent == 11346 or .parent == 11368 or .parent == 11394 or .parent == 11416 or .parent == 11442 or .parent == 11455) and .changed_pixels == 0)] | length' "$json")" -eq 6

# Original firmware requests one frame-boundary erase over the 800x480 main
# screen.  It removes Wait, preserves the separate status line, and is followed
# by the success-panel drawing.
test "$(jq -s '[.[] | select(.event == "scroll_register" and .erase == true and .value == "2001" and .scroll_bounds == ["0000", "0320", "0000", "01E0"])] | length' "$json")" -eq 1
test "$(jq -r 'select(.event == "snapshot_region" and .name == "WAIT" and .target_time == 115) | .bitmap_hash' "$json")" != \
	"$(jq -r 'select(.event == "snapshot_region" and .name == "WAIT" and .target_time == 130) | .bitmap_hash' "$json")"
test "$(jq -r 'select(.event == "snapshot_region" and .name == "WAIT" and .target_time == 130) | .bitmap_hash' "$json")" = "EC3E6705"
test "$(jq -r 'select(.event == "snapshot_region" and .name == "STATUS") | .bitmap_hash' "$json" | sort -u | wc -l | tr -d ' ')" -eq 1
test "$(jq -r 'select(.event == "snapshot_region" and .name == "POST_OK" and .target_time == 115) | .bitmap_hash' "$json")" != \
	"$(jq -r 'select(.event == "snapshot_region" and .name == "POST_OK" and .target_time == 130) | .bitmap_hash' "$json")"

echo "VT340 graphics raster command regression passed"
