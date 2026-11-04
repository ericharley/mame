#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-fast-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-fast-nvram.XXXXXX)
log=$(mktemp -t vt340-fast-start.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log"' EXIT HUP INT TERM

mkdir -p "$config_dir"
cp vt340-research/fixtures/fast-start.cfg "$config_dir/vt340.cfg"

"$binary" vt340 -rompath roms -cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" -video none -sound none -nothrottle \
	-seconds_to_run 20 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/fast-start-regression.lua \
	>"$log" 2>&1

rg -q 'event=checkpoint_value .*value=00 patch=00' "$log"
rg -q 'event=checkpoint_exit .*value=00 patch=00' "$log"
rg -q 'event=native_result value=80' "$log"
rg -q 'event=result_classify A=80 value=80 patch=00' "$log"
rg -q 'FAST_START_PASS native_result=1 elapsed=13\.14[0-9]+' "$log"

echo "VT340 optional fast-start ROM patch passed"
