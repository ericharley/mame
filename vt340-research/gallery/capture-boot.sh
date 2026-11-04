#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output=${VT340_GALLERY_OUTPUT:-$root/vt340-research/gallery/assets/boot-to-ok.gif}
work=$(mktemp -d -t vt340-gallery-boot.XXXXXX)
frames="$work/frames"
config="$work/cfg"
nvram="$work/nvram"
log="$work/boot.log"
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$frames" "$config" "$nvram" "$(dirname -- "$output")"

VT340_GALLERY_FRAME_DIR="$frames" VT340_GALLERY_INTERVAL=${VT340_GALLERY_INTERVAL:-2} \
	VT340_GALLERY_STOP_TIME=${VT340_GALLERY_STOP_TIME:-132} \
	"$binary" vt340 -rompath "$root/roms" -cfg_directory "$config" \
	-nvram_directory "$nvram" -video none -sound none -nothrottle \
	-seconds_to_run 133 -autoboot_delay 0 \
	-autoboot_script "$root/vt340-research/gallery/boot-capture.lua" \
	>"$log" 2>&1

set -- "$frames"/boot-*.png
python3 "$root/vt340-research/gallery/tools/pngs_to_gif.py" \
	--delay-ms 70 --last-delay-ms 1800 "$output" "$@"
echo "VT340 native boot gallery animation: $output"
