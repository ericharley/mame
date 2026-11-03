#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
jobs=${JOBS:-4}

cd "$root"
PATH="/opt/homebrew/bin:$PATH" make -j"$jobs" REGENIE=1 USE_LIBSDL=1 \
	SUBTARGET=dc7051test SOURCES=src/mame/dec/dc7051test.cpp

./dc7051test dc7051test -video none -sound none -nothrottle -seconds_to_run 40
