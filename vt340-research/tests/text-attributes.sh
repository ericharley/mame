#!/bin/sh
set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/vt340-research/tests/lib/artifacts.sh"
run_dir=$(mktemp -d -t vt340-text-attributes.XXXXXX)
nvram="$run_dir/nvram"
log="$run_dir/run.log"
json="$run_dir/events.jsonl"
snapshot=${VT340_TEXT_ATTR_SNAPSHOT:-$(vt340_artifact_path /tmp/vt340-text-attributes.png text-attributes.png)}
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
		echo "VT340 text-attribute evidence preserved after failure: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM
mkdir "$nvram"

VT340_TEXT_ATTR_SNAPSHOT="$snapshot" \
	"$binary" vt340 -rompath "$root/roms" -nvram_directory "$nvram" \
	-comm1 pty -video none -sound none -nothrottle -verbose \
	-seconds_to_run 142 -autoboot_delay 0 \
	-autoboot_script "$root/vt340-research/traces/text-attributes-trace.lua" \
	>"$log" 2>&1 &
pid=$!

endpoint=
for unused in $(seq 1 1800); do
	endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | head -1)
	if test -n "$endpoint" && rg -q 'VT340_TEXT_ATTR_JSON .*"event":"external_ready"' "$log"; then
		break
	fi
	if ! kill -0 "$pid" 2>/dev/null; then
		wait "$pid"
		exit 1
	fi
	sleep 0.05
done
test -n "$endpoint"

if ! stty -f "$endpoint" raw -echo 2>/dev/null; then
	stty -F "$endpoint" raw -echo
fi
printf '\033[2J\033[H\033[0mATTRIBUTE\r\n\033[1mATTRIBUTE\033[0m\r\n\033[4mATTRIBUTE\033[0m\r\n\033[7mATTRIBUTE\033[0m\r\n\033[5mATTRIBUTE\033[0m\r\n\033[0mATTRIBUTE\r\n' >"$endpoint"

wait "$pid"
pid=
rg '^VT340_TEXT_ATTR_JSON ' "$log" | sed 's/^VT340_TEXT_ATTR_JSON //' >"$json"

test "$(jq -s '[.[] | select(.event == "capture")] | length' "$json")" -eq 8

# The native firmware uses raw plane index 14 for ordinary text and index 15
# for bold. Board output-map wiring reverses plane significance, routing them
# to palette entries 7 and 15 respectively. The default configuration
# programs both entries to white, so bold is a separate logical
# intensity/color selection without a fake thickened glyph.
jq -e 'select(.event == "capture" and .target == 140 and
	.normal.hash == "440AD4EB" and .normal.raw[14] == 331 and .normal.mapped[7] == 331 and
	.bold.hash == "07B6B058" and .bold.raw[15] == 331 and .bold.mapped[15] == 331 and
	.palette[7] == "FFFF" and .palette[15] == "FFFF")' "$json" >/dev/null

# Underline adds the complete cell baseline, reverse exchanges the cell field,
# and SGR 0 after every attributed line restores the exact ordinary glyph.
jq -e 'select(.event == "capture" and .target == 140 and
	.underline.hash == "2889C4EB" and .underline.raw[14] == 421 and
	.reverse.hash == "1EA611EB" and .reverse.raw[14] == 1469 and
	.reset.hash == .normal.hash)' "$json" >/dev/null

# Character blink alternates between the native normal and reverse cell forms;
# require both phases without depending on which phase owns a particular frame.
test "$(jq -s '[.[] | select(.event == "capture") | .blink.hash] | unique | length' "$json")" -eq 2
test "$(jq -s '[.[] | select(.event == "capture" and
	(.blink.hash != .normal.hash and .blink.hash != .reverse.hash))] | length' "$json")" -eq 0
test "$(jq -s '[.[] | select(.event == "capture" and .blink.hash == .normal.hash)] | length' "$json")" -gt 0
test "$(jq -s '[.[] | select(.event == "capture" and .blink.hash == .reverse.hash)] | length' "$json")" -gt 0
test -s "$snapshot"

echo "VT340 native text-attribute and palette regression passed"
echo "Snapshot: $snapshot"
