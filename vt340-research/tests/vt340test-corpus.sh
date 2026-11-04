#!/bin/bash
set -euo pipefail

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_root="$root/../sources/vt340test"
cases_file="$root/vt340-research/tests/vt340test-cases.json"
run_root=$(mktemp -d -t vt340-external-corpus.XXXXXX)
pid=

cleanup()
{
	status=$?
	if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if [[ $status -eq 0 ]]; then
		rm -rf "$run_root"
	else
		echo "VT340 external corpus evidence preserved after failure: $run_root" >&2
	fi
}
trap cleanup EXIT HUP INT TERM

[[ -d "$source_root/.git" ]]
expected_revision=$(jq -r '.source_revision' "$cases_file")
observed_revision=$(git -C "$source_root" rev-parse HEAD)
if [[ "$observed_revision" != "$expected_revision" ]]; then
	echo "vt340test revision: expected $expected_revision, observed $observed_revision" >&2
	exit 1
fi

run_case()
{
	local case_id=$1
	local source_path=$2
	local source_sha=$3
	local source_arg=$4
	local expected_bytes_catalog=$5
	local expected_hash=$6
	local expected_nonzero=$7
	local dc323_families=$8
	local color_mode=$9
	local expected_snapshot_sha=${10}
	local case_root="$run_root/$case_id"
	local config="$case_root/cfg"
	local nvram="$case_root/nvram"
	local input="$case_root/input.stream"
	local expected="$case_root/expected.stream"
	local log="$case_root/mame.log"
	local json="$case_root/events.jsonl"
	local snapshot="$case_root/screen.png"
	local artifact_root=${VT340_TEST_ARTIFACT_DIR:-}
	local artifact_case=
	mkdir -p "$config" "$nvram"
	cp "$root/vt340-research/fixtures/fast-start.cfg" "$config/vt340.cfg"

	local observed_source_sha
	observed_source_sha=$(shasum -a 256 "$source_root/$source_path" | awk '{print $1}')
	if [[ "$observed_source_sha" != "$source_sha" ]]; then
		echo "$case_id source hash: expected $source_sha, observed $observed_source_sha" >&2
		exit 1
	fi
	if [[ "$source_arg" != "-" ]]; then
		TERM=vt340 bash "$source_root/$source_path" "$source_arg" >"$input"
	else
		TERM=vt340 bash "$source_root/$source_path" >"$input"
	fi
	# Cursor blink phase depends on when the host finishes writing.  Hide the
	# cursor after the unmodified source stream so framebuffer comparisons cover
	# the program's stable output rather than a periodic 8x16 overlay.
	printf '\033[?25l' >>"$input"
	# Darwin's slave PTY maps generated LF bytes to CRLF on the UART even
	# after raw mode is requested. Give the observer the exact wire stream.
	perl -0777 -pe 's/\n/\r\n/g' "$input" >"$expected"
	local capture_time=50
	local input_ready_time=17
	local run_time=52
	local select_color=0
	if [[ "$color_mode" == "true" ]]; then
		# Use the original firmware's Set-Up path to select VT340 color mode.
		# The established key sequence completes at 270 seconds and releases
		# host input at 280 seconds; no palette is injected by the harness.
		capture_time=300
		input_ready_time=280
		run_time=302
		select_color=1
	fi

	VT340_SIXEL_EXTERNAL=1 VT340_SIXEL_FILE="$expected" VT340_SELECT_COLOR="$select_color" \
		VT340_SIXEL_SNAPSHOT="$snapshot" VT340_SIXEL_CAPTURE_TIME="$capture_time" \
		VT340_LEAVE_POST_TIME=15 VT340_INPUT_READY_TIME="$input_ready_time" \
		"$binary" vt340 -rompath "$root/roms" -cfg_directory "$config" \
		-nvram_directory "$nvram" -comm1 pty -video none -sound none \
		-nothrottle -verbose -seconds_to_run "$run_time" -autoboot_delay 0 \
		-autoboot_script "$root/vt340-research/traces/sixel-bill-trace.lua" \
		>"$log" 2>&1 &
	pid=$!

	local endpoint=
	local ready=0
	for unused in $(seq 1 1800); do
		endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | head -1)
		if [[ -n "$endpoint" ]] && rg -q '"event":"external_ready"' "$log"; then
			ready=1
			break
		fi
		if ! kill -0 "$pid" 2>/dev/null; then
			wait "$pid"
			exit 1
		fi
		sleep 0.1
	done
	[[ $ready -eq 1 ]]
	if ! stty -f "$endpoint" raw -echo 2>/dev/null; then
		stty -F "$endpoint" raw -echo
	fi
	python3 "$root/vt340-research/tests/lib/serial_write.py" "$endpoint" "$input"
	wait "$pid"
	pid=

	rg '^VT340_SIXEL_JSON ' "$log" | sed 's/^VT340_SIXEL_JSON //' >"$json"
	local expected_bytes
	expected_bytes=$(wc -c <"$expected" | tr -d ' ')
	if [[ $expected_bytes -ne $expected_bytes_catalog ]]; then
		echo "$case_id wire bytes: catalog $expected_bytes_catalog, generated $expected_bytes" >&2
		exit 1
	fi
	local received_bytes received_mismatches graphics_commands
	received_bytes=$(jq -r 'select(.event == "capture") | .received_bytes' "$json")
	received_mismatches=$(jq -r 'select(.event == "capture") | .received_mismatches' "$json")
	graphics_commands=$(jq -r 'select(.event == "capture") | .graphics_commands' "$json")
	if [[ $received_bytes -ne $expected_bytes || $received_mismatches -ne 0 ]]; then
		echo "$case_id UART stream: expected $expected_bytes bytes, received $received_bytes, mismatches $received_mismatches" >&2
		exit 1
	fi
	if [[ $graphics_commands -le 0 ]]; then
		echo "$case_id produced no graphics commands" >&2
		exit 1
	fi
	if [[ "$color_mode" == "true" ]]; then
		jq -e 'select(.event == "native_color_setup" and .config == "28" and .state == "38")' "$json" >/dev/null
	fi
	# Keep each declared integration claim tied to command evidence from this
	# particular workload, rather than relying only on its final framebuffer.
	for family in $(printf '%s' "$dc323_families" | tr ',' ' '); do
		case "$family" in
			raster.normal-constant)
				jq -e 'select(.event == "command_count" and (.command | test("^06")) and .count > 0)' "$json" >/dev/null ;;
			raster.normal-bitmap)
				jq -e 'select(.event == "command_count" and (.command | test("^0E")) and .count > 0)' "$json" >/dev/null ;;
			raster.linear-source1)
				jq -e 'select(.event == "mode_count" and .mode == "00C2" and .count > 0)' "$json" >/dev/null ;;
			transfer.processor-to-bitmap-x)
				jq -e 'select(.event == "command_count" and .command == "07D1" and .count > 0)' "$json" >/dev/null ;;
		esac
	done
	local observed_nonzero
	observed_nonzero=$(jq -r 'select(.event == "capture") | .nonzero_pixels' "$json")
	if [[ ! -s "$snapshot" ]]; then
		echo "$case_id did not produce a screenshot" >&2
		exit 1
	fi
	local observed_hash
	observed_hash=$(jq -r 'select(.event == "capture") | .bitmap_hash' "$json")
	local observed_snapshot_sha
	observed_snapshot_sha=$(shasum -a 256 "$snapshot" | awk '{print $1}')
	if [[ ${VT340_UPDATE_BASELINE:-0} != 1 ]]; then
		if [[ $observed_nonzero -ne $expected_nonzero ]]; then
			echo "$case_id nonzero pixels: expected $expected_nonzero, observed $observed_nonzero" >&2
			exit 1
		fi
		if [[ "$observed_hash" != "$expected_hash" ]]; then
			echo "$case_id framebuffer hash: expected $expected_hash, observed $observed_hash" >&2
			exit 1
		fi
		if [[ "$expected_snapshot_sha" != "-" && "$observed_snapshot_sha" != "$expected_snapshot_sha" ]]; then
			echo "$case_id screenshot SHA-256: expected $expected_snapshot_sha, observed $observed_snapshot_sha" >&2
			exit 1
		fi
	fi

	if [[ -n "$artifact_root" ]]; then
		artifact_case="$artifact_root/$case_id"
		mkdir -p "$artifact_case"
		cp "$input" "$artifact_case/input.stream"
		cp "$log" "$artifact_case/mame.log"
		cp "$json" "$artifact_case/events.jsonl"
		cp "$snapshot" "$artifact_case/screen.png"
	fi
	printf '%s hash=%s bytes=%s nonzero=%s screenshot=%s\n' "$case_id" "$observed_hash" \
		"$expected_bytes" "$observed_nonzero" "$observed_snapshot_sha"
}

while IFS='|' read -r case_id source_path source_sha source_arg expected_bytes expected_hash expected_nonzero dc323_families color_mode expected_snapshot_sha; do
	run_case "$case_id" "$source_path" "$source_sha" "$source_arg" \
		"$expected_bytes" "$expected_hash" "$expected_nonzero" "$dc323_families" "$color_mode" "$expected_snapshot_sha"
done < <(jq --arg case_filter "${VT340_CORPUS_CASE:-}" -r '.cases[] |
	select($case_filter == "" or .id == $case_filter) | [
	.id, .source, .source_sha256, (.argument // "-"),
	(.expected_wire_bytes | tostring), .expected_bitmap_hash,
	(.expected_nonzero_pixels | tostring),
	([.dc323_commands[].family] | join(",")),
	(.color_mode // false | tostring),
	(.expected_snapshot_sha256 // "-")] | join("|")' "$cases_file")

echo "VT340 external conformance corpus regression passed"
