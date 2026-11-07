#!/bin/sh

set -eu

binary=${1:-./vt340}
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
run_dir=$(mktemp -d -t vt340-mediacopy-printer.XXXXXX)
nvram="$run_dir/nvram"
log="$run_dir/mame.log"
request="$run_dir/request.bin"
printout="$run_dir/mediacopy.six"
media_copy_target=${VT340_MEDIACOPY_TARGET:-0}
printer_request=${VT340_PRINTER_REQUEST:-mediacopy}
expect_blocked=${VT340_EXPECT_PRINTER_BLOCKED:-0}
pid=
capture_pid=

cleanup()
{
	status=$?
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if [ -n "$capture_pid" ] && kill -0 "$capture_pid" 2>/dev/null; then
		kill "$capture_pid" 2>/dev/null || true
		wait "$capture_pid" 2>/dev/null || true
	fi
	if [ -n "${VT340_TEST_ARTIFACT_DIR:-}" ]; then
		mkdir -p "$VT340_TEST_ARTIFACT_DIR"
		cp "$log" "$VT340_TEST_ARTIFACT_DIR/mame.log" 2>/dev/null || true
		cp "$printout" "$VT340_TEST_ARTIFACT_DIR/mediacopy.six" 2>/dev/null || true
	fi
	if [ "$status" -eq 0 ]; then
		rm -rf "$run_dir"
	else
		echo "VT340 media-copy evidence preserved after failure: $run_dir" >&2
	fi
}
trap cleanup EXIT HUP INT TERM

mkdir "$nvram"
case $printer_request in
mediacopy)
	printf '\033[?%si\033[?43h\033[?44h\033[?45h\033[?46l\033[?47l\033PpS(H(P[0,0])[390,230][409,249])\033\\' "$media_copy_target" >"$request"
	;;
controller)
	printf '\033[5iVT340 printer controller test\r\n\033[4i' >"$request"
	;;
autoprint)
	printf '\033[?5iVT340 auto print test\r\n\033[?4i' >"$request"
	;;
*)
	echo "unknown VT340_PRINTER_REQUEST: $printer_request" >&2
	exit 2
	;;
esac
: >"$printout"

VT340_MEDIACOPY_PRINTER_SETUP=${VT340_MEDIACOPY_PRINTER_SETUP:-level2} \
	"$binary" vt340 -rompath "$root/roms" \
	-nvram_directory "$nvram" -comm1 pty \
	-printer pty \
	-video none -sound none -nothrottle -verbose -debug -debugger none \
	-seconds_to_run 305 \
	-autoboot_delay 0 -autoboot_script "$root/vt340-research/traces/mediacopy-printer-trace.lua" \
	>"$log" 2>&1 &
pid=$!

endpoint=
printer_endpoint=
for unused in $(seq 1 1800); do
	endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | head -1)
	printer_endpoint=$(sed -n 's/.*Pseudo terminal .* opened on \([^ ]*\).*/\1/p' "$log" | sed -n '2p')
	if [ -n "$endpoint" ] && [ -n "$printer_endpoint" ] && rg -q '"event":"external_ready"' "$log"; then
		break
	fi
	if ! kill -0 "$pid" 2>/dev/null; then
		wait "$pid"
		exit 1
	fi
	sleep 0.1
done
[ -n "$endpoint" ]
[ -n "$printer_endpoint" ]

if ! stty -f "$endpoint" raw -echo 2>/dev/null; then
	stty -F "$endpoint" raw -echo
fi
if ! stty -f "$printer_endpoint" raw -echo 2>/dev/null; then
	stty -F "$printer_endpoint" raw -echo
fi
python3 "$root/vt340-research/tests/lib/serial_capture_sixel.py" \
	"$printer_endpoint" "$printout" &
capture_pid=$!
sleep 0.2
python3 "$root/vt340-research/tests/lib/serial_write.py" "$endpoint" "$request"
wait "$pid"
pid=
if kill -0 "$capture_pid" 2>/dev/null; then
	kill "$capture_pid" 2>/dev/null || true
	wait "$capture_pid" 2>/dev/null || true
else
	wait "$capture_pid"
fi
capture_pid=

if [ "$expect_blocked" -eq 1 ]; then
	rg -q 'VT340_MEDIACOPY_FAIL .*bytes=0 sixel=false' "$log"
	rg -q '"event":"printer_route".*"name":"printer_reset".*"queue_count":"00"' "$log"
	rg -q '"event":"printer_uart_read".*"pc":"4E8B".*"data":"11"' "$log"
	if rg -q '"event":"sixel_start"' "$log"; then
		echo "native printer route unexpectedly emitted SIXEL" >&2
		exit 1
	fi
	echo "VT340 native printer routing known-failure diagnostic reproduced"
	exit 0
fi

rg -q 'VT340_MEDIACOPY_PASS .*bytes=' "$log"
rg -q '"event":"sixel_start"' "$log"
[ -s "$printout" ]
printf '\033P' | cmp -n 2 - "$printout"

echo "VT340 native Media Copy to printer regression passed"
