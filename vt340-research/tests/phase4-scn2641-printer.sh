#!/bin/sh
set -eu

binary=${1:-./vt340}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$test_dir/lib/artifacts.sh"
log=$(mktemp -t vt340-phase4-scn2641.XXXXXX)
trap 'vt340_artifact_copy "$log" "mame.log"; rm -f "$log"' EXIT HUP INT TERM

"$binary" vt340 -rompath roms -video none -sound none -nothrottle \
	-seconds_to_run 126 -debug -debugger none -autoboot_delay 0 \
	-autoboot_script vt340-research/traces/phase4-scn2641-printer-diagnostic.lua \
	>"$log" 2>&1

# The first configuration is MR2=71 followed by MR1=CA.  MR2 must survive
# the later MR1 write, and the reset value MR1=00 must not start the
# asynchronous-only SCN2641 in the shared PCI/EPCI synchronous state machine.
rg -q 'op=W pc=F7DC address=F012 data=71' "$log"
rg -q 'op=W pc=F7FB address=F012 data=CA' "$log"
rg -q 'op=R pc=F81E address=F003 data=A2' "$log"

# Verify the first native local-loopback transfer end to end: TxRDY before
# THR load, TxRDY/RxRDY/TxEMT with no error flags after serialization, and an
# identical byte in RHR.
rg -q 'event=status_txrdy_branch .*A=C1 .*R2=00 .*R4=05' "$log"
rg -q 'op=W pc=F771 address=F010 data=0A .*R2=00' "$log"
rg -q 'event=status_rxrdy_branch .*A=C7 .*R2=00 .*R4=0A' "$log"
rg -q 'event=status_error_branch .*A=00 .*R2=00 .*R4=0A' "$log"
rg -q 'op=R pc=F78A address=F000 data=0A .*R2=00' "$log"

# The firmware exercises ten internal baud rates and seven framing/parity
# formats in 18 transfers.  Every transfer must reach RHR without taking the
# diagnostic failure path, and POST must remain clear.
test "$(rg -c 'event=loopback_iteration' "$log")" -eq 18
test "$(rg -c 'op=W .*address=F010' "$log")" -eq 18
test "$(rg -c 'op=R .*address=F000' "$log")" -eq 18
if rg -q 'event=(iteration_fail|printer_bit6_set)' "$log"; then
	echo "SCN2641 printer diagnostic failure path was taken" >&2
	exit 1
fi
rg -q 'event=printer_pass_return result=00' "$log"
rg -q 'event=command32_submit result=00' "$log"
rg -q 'PHASE4_SCN2641_PASS .*result=00' "$log"

echo "VT340 Phase 4 SCN2641 printer diagnostic regression passed"
