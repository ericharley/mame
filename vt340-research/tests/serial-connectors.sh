#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
slots=$(mktemp -t vt340-serial-slots.XXXXXX)
devices=$(mktemp -t vt340-serial-devices.XXXXXX)
log=$(mktemp -t vt340-serial-post.XXXXXX)
defaults_log=$(mktemp -t vt340-serial-defaults.XXXXXX)
config_dir=$(mktemp -d -t vt340-serial-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-serial-nvram.XXXXXX)
trap 'vt340_artifact_copy "$slots" "slots.txt"; vt340_artifact_copy "$devices" "devices.txt"; vt340_artifact_copy "$defaults_log" "defaults.log"; vt340_artifact_copy "$log" "mame.log"; rm -f "$slots" "$devices" "$defaults_log" "$log"; rm -rf "$config_dir" "$nvram_dir"' EXIT HUP INT TERM

"$binary" -listslots vt340 >"$slots"
rg -q 'comm1' "$slots"
rg -q 'comm2' "$slots"
test "$(rg -c 'Pseudo Terminal' "$slots")" -eq 2

"$binary" vt340 -comm1 pty -comm2 pty -listdevices >"$devices"
test "$(rg -c 'Pseudo Terminal' "$devices")" -eq 2

# A scrolling region can make the terminal send XOFF while it moves and
# redraws rows.  The host connector must honor that signal by default or a
# live PTY can overrun the firmware and produce corrupted text.
"$binary" vt340 -rompath roms -comm1 pty \
	-cfg_directory "$config_dir" -nvram_directory "$nvram_dir" \
	-video none -sound none -nothrottle -seconds_to_run 1 \
	-autoboot_delay 0 \
	-autoboot_script vt340-research/traces/serial-flow-default-trace.lua \
	>"$defaults_log" 2>&1
rg -q 'VT340_SERIAL_DEFAULT_PASS flow=04' "$defaults_log"

# Attaching both host ports must not alter the native serial diagnostics or
# the zero POST result.
"$binary" vt340 -rompath roms -comm1 pty -comm2 pty \
	-cfg_directory "$config_dir" -nvram_directory "$nvram_dir" \
	-video none -sound none -nothrottle -seconds_to_run 126 \
	-debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-cpu1-bit0-diagnostic.lua \
	>"$log" 2>&1

rg -q 'event=command32_submit result=00' "$log"
rg -q 'PHASE4_BIT0_PASS reads=574' "$log"

echo "VT340 external serial connector regression passed"
