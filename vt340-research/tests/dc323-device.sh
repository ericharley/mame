#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
jobs=${JOBS:-4}

cd "$root"
PATH="/opt/homebrew/bin:$PATH" make -j"$jobs" REGENIE=1 USE_LIBSDL=1 \
	SUBTARGET=dc323test SOURCES=src/mame/dec/dc323test.cpp

./dc323test dc323test -video none -sound none -seconds_to_run 2
