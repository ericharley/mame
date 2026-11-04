#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
config_dir=$(mktemp -d -t vt340-phase4-pbt-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-phase4-pbt-nvram.XXXXXX)
log=$(mktemp -t vt340-phase4-pbt.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -rf "$config_dir" "$nvram_dir"; rm -f "$log"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" -video none -sound none -nothrottle \
	-seconds_to_run 126 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-pbt-provenance.lua \
	>"$log" 2>&1

rg -q 'registers=.*07=0034 .*08=0BC4 .*22=0000 .*23=12E4 .*26=0100 .*29=0020' "$log"
rg -q 'event=transfer_done fifo_reads=1024 stored=1024 first=57 last=FF text=5654330030204F4B4572726F72202D19' "$log"
rg -q 'PHASE4_PBT_PASS' "$log"

echo "VT340 Phase 4 bitmap-to-processor transfer regression passed"
