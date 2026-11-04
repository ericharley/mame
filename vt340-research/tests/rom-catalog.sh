#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

cd "$root"
vt340-research/tools/rom_catalog.py verify --profile vt340-v1.1-working
vt340-research/tools/rom_catalog.py verify --profile vt340-v1.1-working --location active
"$binary" -verifyroms vt340 -rompath roms | rg -q '1 romsets found, 1 were OK'

echo "VT340 versioned ROM catalog regression passed"
