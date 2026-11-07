#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/vt340-research/tests/lib/artifacts.sh"
run_dir=$(mktemp -d -t vt340-vttest-screen.XXXXXX)
config="$run_dir/cfg"
nvram="$run_dir/nvram"
input="$run_dir/input.stream"
expected="$run_dir/expected.stream"
log="$run_dir/mame.log"
json="$run_dir/events.jsonl"
snapshot=${VT340_VTTEST_SNAPSHOT:-$(vt340_artifact_path /tmp/vt340-vttest-screen-features.png vttest-screen-features.png)}
pid=

cleanup()
{
	status=$?
	if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	vt340_artifact_copy "$log" "mame.log"
	vt340_artifact_copy "$json" "events.jsonl"
	if test "$status" -eq 0; then
		rm -rf "$run_dir"
	else
		echo "VTTEST screen-feature evidence preserved after failure: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM
mkdir "$config" "$nvram"
cp "$root/vt340-research/fixtures/fast-start.cfg" "$config/vt340.cfg"
{
	sh "$root/vt340-research/fixtures/vttest-screen-features.sh" all
	sh "$root/vt340-research/fixtures/vttest-screen-features.sh" save-restore
} >"$input"
# Darwin's slave PTY maps generated LF bytes to CRLF on the UART.
perl -0777 -pe 's/\n/\r\n/g' "$input" >"$expected"

VT340_SIXEL_EXTERNAL=1 VT340_SIXEL_FILE="$expected" \
	VT340_SIXEL_SNAPSHOT="$snapshot" VT340_SIXEL_CAPTURE_TIME=55 \
	VT340_LEAVE_POST_TIME=15 VT340_INPUT_READY_TIME=17 \
	"$binary" vt340 -rompath "$root/roms" -cfg_directory "$config" \
	-nvram_directory "$nvram" -comm1 pty -video none -sound none \
	-nothrottle -verbose -seconds_to_run 57 -autoboot_delay 0 \
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

rg '^VT340_SIXEL_JSON ' "$log" | sed 's/^VT340_SIXEL_JSON //' >"$json"
expected_bytes=$(wc -c <"$expected" | tr -d ' ')
test "$(jq -r 'select(.event == "capture") | .received_bytes' "$json")" -eq "$expected_bytes"
test "$(jq -r 'select(.event == "capture") | .received_mismatches' "$json")" -eq 0
test "$(jq -r 'select(.event == "capture") | .y_limit' "$json")" = "020A"
test "$(jq -r 'select(.event == "capture") | .flow_control.xoff' "$json")" -gt 0
test -s "$snapshot"

hash=$(jq -r 'select(.event == "capture") | .bitmap_hash' "$json")
test "$hash" = "BB084B05"
echo "VTTEST screen-feature transition regression passed (hash=$hash)"
echo "Snapshot: $snapshot"
