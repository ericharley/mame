#!/bin/sh
# Exercise screen scrolling/rendition before the double-height blink pattern.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

sh "$root/vt340-research/fixtures/vttest-screen-features.sh" all
sh "$root/vt340-research/fixtures/vttest-screen-features.sh" save-restore
sh "$root/vt340-research/fixtures/vttest-double-size-blink.sh"
