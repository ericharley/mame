#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# The first 4 KiB of the Bill fixture selects every SIXEL color while avoiding
# the separate sustained-stream DCS/flow-control race. Require all sixteen
# framebuffer indices to become visible through the native firmware path.
export VT340_SIXEL_BYTE_LIMIT=4096
export VT340_SIXEL_CAPTURE_TIME=340
export VT340_SIXEL_SNAPSHOT=${VT340_SIXEL_SNAPSHOT:-/tmp/vt340-sixel-color-indices.png}
exec "$root/vt340-research/tests/sixel-bill-pty.sh" "$binary"
