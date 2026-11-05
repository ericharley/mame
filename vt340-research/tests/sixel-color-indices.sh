#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# The first 4 KiB of the Bill fixture selects every SIXEL color while avoiding
# the separate sustained-stream DCS/flow-control race. Its painted pixels use
# 15 framebuffer indices; index 8 in an older passing capture came solely from
# the independently blinking 10x20 text cursor. Exhaustive 0-15 index routing
# belongs to the firmware-free dc323-device regression.
export VT340_SIXEL_BYTE_LIMIT=4096
export VT340_SIXEL_CAPTURE_TIME=340
export VT340_MIN_COLOR_INDICES=15
if test -n "${VT340_TEST_ARTIFACT_DIR:-}"; then
	export VT340_SIXEL_SNAPSHOT=${VT340_SIXEL_SNAPSHOT:-$VT340_TEST_ARTIFACT_DIR/sixel-color-indices.png}
else
	export VT340_SIXEL_SNAPSHOT=${VT340_SIXEL_SNAPSHOT:-/tmp/vt340-sixel-color-indices.png}
fi
exec "$root/vt340-research/tests/sixel-bill-pty.sh" "$binary"
