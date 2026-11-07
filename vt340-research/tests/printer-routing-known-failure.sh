#!/bin/sh

set -eu

binary=${1:-./vt340}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

VT340_EXPECT_PRINTER_BLOCKED=1 \
	VT340_MEDIACOPY_PRINTER_SETUP=none \
	VT340_MEDIACOPY_TIMEOUT=143 \
	VT340_MEDIACOPY_TARGET=0 \
	"$script_dir/mediacopy-printer.sh" "$binary"
