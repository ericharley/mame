#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$root/vt340-research/fixtures/bill-the-cat.six"
run_dir=$(mktemp -d -t vt340-sixel-pty.XXXXXX)
nvram="$run_dir/nvram"
log="$run_dir/run.log"
json="$run_dir/run.json"
snapshot=${VT340_SIXEL_SNAPSHOT:-/tmp/vt340-sixel-bill-color.png}
capture_time=${VT340_SIXEL_CAPTURE_TIME:-560}
run_time=$((capture_time + 5))
byte_limit=${VT340_SIXEL_BYTE_LIMIT:-0}
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
		echo "VT340 color SIXEL evidence preserved after failure: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM
mkdir "$nvram"

VT340_SELECT_COLOR=1 VT340_SIXEL_EXTERNAL=1 \
	VT340_SIXEL_FILE="$fixture" VT340_SIXEL_SNAPSHOT="$snapshot" \
	VT340_SIXEL_CAPTURE_TIME="$capture_time" \
	"$binary" vt340 -rompath "$root/roms" -nvram_directory "$nvram" \
	-comm1 pty -video none -sound none -nothrottle -verbose \
	-seconds_to_run "$run_time" -autoboot_delay 0 \
	-autoboot_script "$root/vt340-research/traces/sixel-bill-trace.lua" \
	>"$log" 2>&1 &
pid=$!

endpoint=
for unused in $(seq 1 1800); do
	endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | head -1)
	if test -n "$endpoint" && rg -q '"event":"external_ready"' "$log"; then
		break
	fi
	if ! kill -0 "$pid" 2>/dev/null; then
		wait "$pid"
		exit 1
	fi
	sleep 0.1
done
test -n "$endpoint"

if ! stty -f "$endpoint" raw -echo 2>/dev/null; then
	stty -F "$endpoint" raw -echo
fi
if test "$byte_limit" -gt 0; then
	dd if="$fixture" of="$endpoint" bs="$byte_limit" count=1 status=none
	expected_bytes=$byte_limit
else
	cat "$fixture" >"$endpoint"
	expected_bytes=$(wc -c < "$fixture" | tr -d ' ')
fi
wait "$pid"
pid=

rg '^VT340_SIXEL_JSON ' "$log" | sed 's/^VT340_SIXEL_JSON //' >"$json"

test "$(jq -r 'select(.event == "capture") | .received_bytes' "$json")" -eq "$expected_bytes"
test "$(jq -r 'select(.event == "capture") | .received_mismatches' "$json")" -eq 0
test "$(jq -s '[.[] | select(.event == "native_color_setup" and .config == "28" and .state == "38")] | length' "$json")" -eq 1
test "$(jq -s '[.[] | select(.event == "palette" and .index == 11 and .rg == "AE" and .gb == "81")] | length' "$json")" -eq 1
test "$(jq -s '[.[] | select(.event == "select_count" and .select == "F" and .count > 0)] | length' "$json")" -eq 1
test "$(jq -r 'select(.event == "capture") | [.color_counts[] | select(. > 0)] | length' "$json")" -eq 16
test -s "$snapshot"

echo "VT340 native color SIXEL PTY regression passed"
echo "Snapshot: $snapshot"
