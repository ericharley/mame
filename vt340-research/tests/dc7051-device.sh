#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
jobs=${JOBS:-4}
state_dir=$(mktemp -d -t vt340-dc7051-state.XXXXXX)
first_log=$(mktemp -t vt340-dc7051-save.XXXXXX)
trap 'rm -rf "$state_dir"; rm -f "$first_log"' EXIT HUP INT TERM

cd "$root"

if rg -n 'frame_enable_w' src/devices/video/dc7051.* src/mame/dec/vt340.cpp; then
	echo "DC323 interrupt masking still controls DC7051 frame scheduling" >&2
	exit 1
fi

PATH="/opt/homebrew/bin:$PATH" make -j"$jobs" REGENIE=1 USE_LIBSDL=1 \
	SUBTARGET=dc7051test SOURCES=src/mame/dec/dc7051test.cpp

./dc7051test dc7051test -video none -sound none -nothrottle -autosave \
	-state_directory "$state_dir" -seconds_to_run 5 >"$first_log" 2>&1

test -n "$(find "$state_dir" -type f -name '*.sta' -print -quit)"

./dc7051test dc7051test -video none -sound none -nothrottle -autosave \
	-state_directory "$state_dir" -seconds_to_run 40
