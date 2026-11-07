#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

VT340_DOUBLE_SIZE_FIXTURE="$root/vt340-research/fixtures/vttest-screen-then-double.sh"
VT340_DOUBLE_SIZE_CAPTURE_TIME=75
VT340_DOUBLE_SIZE_EXPECTED_HASHES="0FB2B197 C32C57DF"
export VT340_DOUBLE_SIZE_FIXTURE VT340_DOUBLE_SIZE_CAPTURE_TIME VT340_DOUBLE_SIZE_EXPECTED_HASHES

exec "$root/vt340-research/tests/vttest-double-size-blink.sh" "${1:-./vt340}"
