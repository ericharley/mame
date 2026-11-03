#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# The visual regression uses the same pseudo-terminal path as a macOS/getty
# session. The bitbanger's shared bidirectional file position is not a faithful
# transport for a sustained XON/XOFF-controlled SIXEL stream.
exec "$root/vt340-research/tests/sixel-bill-pty.sh" "$binary"
