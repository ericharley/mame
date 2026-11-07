#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
run_dir=$(mktemp -d -t vt340-vttest-double-size.XXXXXX)
config="$run_dir/cfg"
nvram="$run_dir/nvram"
input="$run_dir/input.stream"
expected="$run_dir/expected.stream"
log=${VT340_DOUBLE_SIZE_LOG:-$run_dir/mame.log}
snapshot=${VT340_DOUBLE_SIZE_SNAPSHOT:-/tmp/vt340-vttest-double-size.png}
capture_time=${VT340_DOUBLE_SIZE_CAPTURE_TIME:-24}
run_seconds=$(awk "BEGIN { print int($capture_time + 3) }")
pid=

cleanup()
{
	status=$?
	if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if test "$status" -eq 0 && test -z "${VT340_KEEP_RUN:-}"; then
		rm -rf "$run_dir"
	else
		echo "VTTEST double-size evidence: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM

mkdir "$config" "$nvram"
cp "$root/vt340-research/fixtures/fast-start.cfg" "$config/vt340.cfg"
sh "$root/vt340-research/fixtures/vttest-double-size-blink.sh" >"$input"
# Darwin's slave PTY maps generated LF bytes to CRLF on the UART.
perl -0777 -pe 's/\n/\r\n/g' "$input" >"$expected"

VT340_SIXEL_EXTERNAL=1 VT340_SIXEL_FILE="$expected" \
	VT340_SIXEL_SNAPSHOT="$snapshot" VT340_SIXEL_CAPTURE_TIME="$capture_time" \
	VT340_LEAVE_POST_TIME=15 VT340_INPUT_READY_TIME=17 VT340_TRACE_RASTER=1 \
	"$binary" vt340 -rompath "$root/roms" -cfg_directory "$config" \
	-nvram_directory "$nvram" -comm1 pty -video none -sound none \
	-nothrottle -verbose -seconds_to_run "$run_seconds" -autoboot_delay 0 \
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
python3 "$root/vt340-research/tests/lib/serial_write.py" "$endpoint" "$input"
wait "$pid"
pid=

expected_bytes=$(wc -c <"$expected" | tr -d ' ')
received_bytes=$(sed -n 's/.*"event":"capture".*"received_bytes":\([0-9][0-9]*\).*/\1/p' "$log")
received_mismatches=$(sed -n 's/.*"event":"capture".*"received_mismatches":\([0-9][0-9]*\).*/\1/p' "$log")
hash=$(sed -n 's/.*"event":"capture".*"bitmap_hash":"\([0-9A-F]*\)".*/\1/p' "$log")
test "$received_bytes" -eq "$expected_bytes"
test "$received_mismatches" -eq 0
test "$hash" = "0FB2B197"
test -s "$snapshot"
echo "VTTEST double-size blink capture passed (bytes=$received_bytes hash=$hash)"
echo "Snapshot: $snapshot"
echo "Log: $log"
