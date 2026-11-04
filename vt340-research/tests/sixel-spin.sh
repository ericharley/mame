#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
animation="$root/../sources/vt340test/sixeltests/animation.sh"
run_dir=$(mktemp -d -t vt340-sixel-spin.XXXXXX)
generated_script="$run_dir/animation-initial.sh"
initial_input="$run_dir/initial-input.six"
shifted_input="$run_dir/shifted-input.six"
palette_shift="$run_dir/palette-shift.six"
initial_expected="$run_dir/initial-expected.six"
shifted_expected="$run_dir/shifted-expected.six"
initial_snapshot=${VT340_SPIN_PHASE1_SNAPSHOT:-/tmp/vt340-spin-phase1.png}
shifted_snapshot=${VT340_SPIN_PHASE2_SNAPSHOT:-/tmp/vt340-spin-phase2.png}
pid=

cleanup()
{
	status=$?
	if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if test "$status" -eq 0; then
		rm -rf "$run_dir"
	else
		echo "VT340 SIXEL spin evidence preserved after failure: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM

# Run the original setup, palette, and ball drawing code, but stop just before
# its intentionally infinite animation loop and suppress its exit cleanup.
perl -0777 -pe '
	s/trap cleanup EXIT/trap - EXIT/;
	s/(spin_ball\(\) \{.*?local step=0\n)  while true.*?\n  done\n\}/$1  return\n\}/s
' "$animation" >"$generated_script"
bash -n "$generated_script"
bash "$generated_script" spin </dev/null >"$initial_input"

# This is update_palette(7, 1) from animation.sh.  It changes only palette
# definitions; no SIXEL bitmap data or positioning controls are sent.
i=0
while test "$i" -lt 14; do
	cn=$((i + 1))
	rgb=$(((i + 7) % 14))
	if test "$rgb" -lt 1; then rgb='100;86;86'
	elif test "$rgb" -lt 7; then rgb='100;100;100'
	else rgb='100'
	fi
	printf '#%d;2;%s' "$cn" "$rgb" >>"$palette_shift"
	i=$((i + 1))
done
initial_bytes=$(wc -c <"$initial_input" | tr -d ' ')
cp "$initial_input" "$shifted_input"
dd if="$palette_shift" of="$shifted_input" bs=1 seek="$initial_bytes" conv=notrunc 2>/dev/null

# The macOS PTY presents shell newlines to the UART as CRLF.  Give the trace
# the exact on-wire stream while retaining the original files for transmission.
perl -0777 -pe 's/\n/\r\n/g' "$initial_input" >"$initial_expected"
perl -0777 -pe 's/\n/\r\n/g' "$shifted_input" >"$shifted_expected"

run_phase()
{
	phase=$1
	input=$2
	expected=$3
	snapshot=$4
	log="$run_dir/$phase.log"
	json="$run_dir/$phase.json"
	nvram="$run_dir/nvram-$phase"
	mkdir "$nvram"

	VT340_SELECT_COLOR=1 VT340_SIXEL_EXTERNAL=1 \
		VT340_SIXEL_FILE="$expected" VT340_SIXEL_SNAPSHOT="$snapshot" \
		VT340_SIXEL_CAPTURE_TIME=560 \
		"$binary" vt340 -rompath "$root/roms" -nvram_directory "$nvram" \
		-comm1 pty -video none -sound none -nothrottle -verbose \
		-seconds_to_run 565 -autoboot_delay 0 \
		-autoboot_script "$root/vt340-research/traces/sixel-bill-trace.lua" \
		>"$log" 2>&1 &
	pid=$!

	endpoint=
	ready=0
	for unused in $(seq 1 3000); do
		endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | head -1)
		if test -n "$endpoint" && rg -q '"event":"external_ready"' "$log"; then ready=1; break; fi
		if ! kill -0 "$pid" 2>/dev/null; then wait "$pid"; exit 1; fi
		sleep 0.1
	done
	test "$ready" -eq 1
	if ! stty -f "$endpoint" raw -echo 2>/dev/null; then
		stty -F "$endpoint" raw -echo
	fi
	cat "$input" >"$endpoint"
	wait "$pid"
	pid=
	rg '^VT340_SIXEL_JSON ' "$log" | sed 's/^VT340_SIXEL_JSON //' >"$json"
}

run_phase initial "$initial_input" "$initial_expected" "$initial_snapshot"
run_phase shifted "$shifted_input" "$shifted_expected" "$shifted_snapshot"

initial_json="$run_dir/initial.json"
shifted_json="$run_dir/shifted.json"
initial_hash=$(jq -r 'select(.event == "capture") | .bitmap_hash' "$initial_json")
shifted_hash=$(jq -r 'select(.event == "capture") | .bitmap_hash' "$shifted_json")
initial_palette=$(jq -s -r '[.[] | select(.event == "palette") | .rg + .gb] | join("")' "$initial_json")
shifted_palette=$(jq -s -r '[.[] | select(.event == "palette") | .rg + .gb] | join("")' "$shifted_json")
initial_png=$(shasum -a 256 "$initial_snapshot" | awk '{print $1}')
shifted_png=$(shasum -a 256 "$shifted_snapshot" | awk '{print $1}')

test "$initial_hash" = "$shifted_hash"
test "$initial_palette" != "$shifted_palette"
test "$initial_png" != "$shifted_png"
for json in "$initial_json" "$shifted_json"; do
	test "$(jq -r 'select(.event == "capture") | .received_mismatches' "$json")" -eq 0
	test "$(jq -r 'select(.event == "capture") | [.color_counts[] | select(. > 0)] | length' "$json")" -eq 16
done
test -s "$initial_snapshot"
test -s "$shifted_snapshot"

echo "VT340 native SIXEL palette-spin regression passed"
echo "Bitmap hash (both phases): $initial_hash"
echo "Palette-only bytes: $(wc -c <"$palette_shift" | tr -d ' ')"
echo "Initial snapshot: $initial_snapshot"
echo "Shifted snapshot: $shifted_snapshot"
