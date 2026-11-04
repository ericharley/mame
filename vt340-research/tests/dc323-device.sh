#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
jobs=${JOBS:-4}
mame_build_path=${MAME_BUILD_PATH:-/opt/homebrew/bin}

cd "$root"

if rg -n '0x(1bd1|2900|bba0|bbaa|bbb4)' src/mame/dec/vt340.cpp; then
	echo "PC-qualified DC323 POST shim found in production driver" >&2
	exit 1
fi

PATH="$mame_build_path:$PATH" make -j"$jobs" REGENIE=1 USE_LIBSDL=1 \
	SUBTARGET=dc323test SOURCES=src/mame/dec/dc323test.cpp

./dc323test dc323test -video none -sound none -seconds_to_run 2
