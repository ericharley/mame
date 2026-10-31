#!/bin/sh
set -eu

binary=${1:-./vt340}

"$binary" -listfull vt340 | rg -q 'VT340 Video Terminal'
"$binary" -verifyroms vt340 -rompath roms | rg -q '1 romsets found, 1 were OK'
"$binary" vt340 -rompath roms -video none -sound none -seconds_to_run 1

echo "VT340 smoke test passed"
