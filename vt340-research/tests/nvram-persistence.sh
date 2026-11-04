#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/vt340-nvram-test.XXXXXX")
write_log="$test_root/write.log"
reload_log="$test_root/reload.log"
trap 'vt340_artifact_copy "$write_log" "save.log"; vt340_artifact_copy "$reload_log" "reload.log"; vt340_artifact_copy "$test_root/vt340/eeprom" "eeprom.bin"; rm -rf "$test_root"' EXIT HUP INT TERM

common_args="vt340 -rompath roms -video none -sound none -skip_gameinfo -nothrottle -nvram_directory $test_root -autoboot_delay 0"

"$binary" $common_args -seconds_to_run 172 \
	-autoboot_script vt340-research/traces/nvram-save-trace.lua >"$write_log" 2>&1

grep -q 'VT340_NVRAM_SAVE_SUMMARY byte_06c=82 byte_06d=E8' "$write_log"
test "$(wc -c < "$test_root/vt340/eeprom" | tr -d ' ')" = 512
test "$(od -An -tx1 -j 108 -N 1 "$test_root/vt340/eeprom" | tr -d ' ')" = 82
test "$(od -An -tx1 -j 109 -N 1 "$test_root/vt340/eeprom" | tr -d ' ')" = e8

"$binary" $common_args -seconds_to_run 150 \
	-autoboot_script vt340-research/traces/nvram-reload-trace.lua >"$reload_log" 2>&1

grep -q 'VT340_NVRAM_RELOAD_SUMMARY byte_06c=82 byte_06d=E8 visible_hash=' "$reload_log"

echo "VT340 native E80 NVRAM persistence regression passed"
