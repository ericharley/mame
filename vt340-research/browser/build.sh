#!/bin/sh
set -eu

# Activate Emscripten >=6.0.2 before running this script.
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

embuilder build sdl3 sdl3_ttf
emmake make -j"${JOBS:-6}" SUBTARGET=vt340web \
  SOURCES=src/mame/dec/vt340.cpp,src/mame/dec/lk201.cpp \
  MACHINES=68681,SCN_PCI,EEPROMDEV SYMBOLS=0 OPTIMIZE=s NOWERROR=1 "$@"
python3 vt340-research/browser/package.py
