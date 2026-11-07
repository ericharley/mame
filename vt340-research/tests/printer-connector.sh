#!/bin/sh

set -eu

binary=${1:-./vt340}
test_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
artifact_dir=${VT340_TEST_ARTIFACT_DIR:-}
printer_output=$(mktemp -t vt340-printer-connector.XXXXXX)
log=$(mktemp -t vt340-printer-connector-log.XXXXXX)
raw_capture=$(mktemp -t vt340-mediacopy-raw.XXXXXX)
expected_sixel=$(mktemp -t vt340-mediacopy-expected.XXXXXX)
extracted_sixel=$(mktemp -t vt340-mediacopy-extracted.XXXXXX)
config_dir=$(mktemp -d -t vt340-printer-config.XXXXXX)
nvram_dir=$(mktemp -d -t vt340-printer-nvram.XXXXXX)

cleanup()
{
	rm -rf "$config_dir" "$nvram_dir"
	rm -f "$printer_output" "$log" "$raw_capture" "$expected_sixel" "$extracted_sixel"
}
trap cleanup EXIT HUP INT TERM

# This test owns the UART after POST.  Use the project's checksum-preserving
# fast-start option so the connector check does not spend two host minutes in
# the separately covered native checkpoint timeout.
cp "$test_root/vt340-research/fixtures/fast-start.cfg" "$config_dir/vt340.cfg"

"$binary" vt340 \
	-rompath "$test_root/roms" \
	-cfg_directory "$config_dir" \
	-nvram_directory "$nvram_dir" \
	-printer printer \
	-printout "$printer_output" \
	-autoboot_script "$test_root/vt340-research/traces/printer-connector-smoke.lua" \
	-video none -sound none -nothrottle -seconds_to_run 20 \
	>"$log" 2>&1

printf 'VT340 PRINTER\r\n' | cmp -s - "$printer_output" || {
	echo "SCN2641 printer connector output mismatch" >&2
	od -An -tx1 "$printer_output" >&2
	exit 1
}
rg -q 'VT340_PRINTER_PASS .*bytes=15' "$log"

# A VT340 media copy may prefix the image with ST, newline, and SSU. Verify
# that the user-facing helper extracts exactly the SIXEL DCS through its ST.
printf '\033P0;1;6q"1;1;4;6#1;2;100;0;0#1~\033\\' >"$expected_sixel"
printf '\033\\\n\033[2 Iignored%safter' "$(cat "$expected_sixel")" >"$raw_capture"
"$test_root/vt340-research/tools/vt340-mediacopy" \
	--extract "$raw_capture" --output "$extracted_sixel"
cmp -s "$expected_sixel" "$extracted_sixel" || {
	echo "VT340 media-copy SIXEL extraction mismatch" >&2
	exit 1
}

if [ -n "$artifact_dir" ]; then
	mkdir -p "$artifact_dir"
	cp "$printer_output" "$artifact_dir/printer-output.prn"
	cp "$extracted_sixel" "$artifact_dir/mediacopy.six"
	cp "$log" "$artifact_dir/mame.log"
fi

echo "VT340 SCN2641 external printer connector regression passed"
