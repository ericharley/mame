#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

for test_name in \
	phase3-checkpoint.sh \
	phase4-ring-drain.sh \
	setup-screen.sh \
	serial-connectors.sh \
	graphics-raster-commands.sh \
	nvram-persistence.sh
do
	"$root/vt340-research/tests/$test_name" "$binary"
done

echo "VT340 DC323 extraction integration regression passed"
