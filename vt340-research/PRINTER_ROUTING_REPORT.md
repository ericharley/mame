# VT340 printer routing investigation

## Scope and result

This investigation added the physical SCN2641 printer connector and traced why
native VT340 output still does not reach it. The serial transport is working,
but the original ROM does not enqueue printer bytes in the tested runtime
configuration. The exact unresolved decision is now bounded to CPU1's printer
service gate at `A8A4`/`ADFF`; this is not an SCN2641 transmit, baud-rate,
flow-control, DSR, ReGIS, or SIXEL-generation failure.

The bottom-row `Printer: None` text is normal idle status content. It is not a
direct display of the electrical DSR input and does not change merely because
an endpoint asserts DSR.

## Hardware implemented

The terminal-control-module schematic gives the following printer path:

- SCN2641 E81 TxD to printer TxD;
- E81 RTS used as printer DTR;
- printer RxD to E81 RxD;
- E81 active-low CTS and DCD tied asserted on the board;
- printer DSR through E63 to active-low `PTRDSR L`, resolved at CPU1 P1.3.

The driver exposes this as the `printer` RS-232 slot with recovered factory
framing of 9600 baud, eight data bits, no parity, and one stop bit. P1.3 must be
treated as both an external resolved input and the output latch used by the E80
EEPROM select circuit. A small MCS-51 read-only latch accessor keeps those two
electrical meanings separate.

## Confirmed observations

1. Native SCN2641 POST still passes.
2. A fresh, isolated E80 image still passes its native checksum test. A stale
   developer NVRAM image initially produced misleading failures; all affected
   regression scripts now use private temporary NVRAM directories.
3. With a printer PTY attached, CPU1 reads resolved P1 as `54`, including
   asserted active-low DSR on bit 3.
4. A real XON (`11`) sent by the printer PTY is received through E81. CPU1 reads
   it at `4E8B` and takes the native XON path.
5. `CSI ?2i` followed by the cropped ReGIS hardcopy command naturally emits a
   SIXEL DCS on Comm 1. The first `ESC P` appears at 141.137888 emulated
   seconds. This proves the parser, hardcopy request, and bitmap-to-SIXEL path.
6. The same request with `CSI ?0i` produces no SCN2641 data writes. Selecting
   Printer Set-Up level 2 and changing flow control from XON/XOFF to DTR through
   the real UI do not change the result.
7. Printer-controller mode (`CSI 5 i`) and auto-print mode (`CSI ?5 i`) also
   produce no printer data, so the failure is broader than graphics media copy.
8. Destination 0 is accepted rather than ignored. Immediately after parsing,
   internal byte `$24` differs (`86` for target 0, `06` for target 2) and `$2B`
   differs (`02` versus `00`).
9. The normal printer service call at `A8A4` enters `ADFF`. With CPU1 P1.2 high,
   execution reaches `AE37`, clears ring count `7CCF` and parser state `7CC7`,
   and returns without reaching printer processing entry `A8AA`. No byte is
   ever submitted to the SCN2641 transmit-data register.

Curated event excerpts are stored in
`traces/printer-routing/target0-events.jsonl` and
`traces/printer-routing/target2-events.jsonl`.

## Conditions ruled out

- Missing printer TxD/RxD wiring.
- Incorrect 9600 8N1 endpoint defaults.
- SCN2641 local-loopback or parity behavior; native POST passes.
- Missing DSR assertion.
- Missing XON or DTR flow-control selection.
- Level-1 SIXEL bugs; level 2 was selected through Set-Up and failed identically.
- ReGIS hardcopy generation; the host route emits native SIXEL.
- A missing external printer signal on P1.2. The schematic identifies P1.2 as
  `MDA H` and routes it to the E58 memory-control PAL input. Printer DSR is the
  separate P1.3 net.

## Exact unresolved point

The unresolved question is why the original runtime expects the `ADFF` gate to
permit `A8AA` printer processing. The observed P1.2 value is high, and the ROM
therefore repeatedly takes the `AE37` reset path. The executable references
test P1.2 at `4E30`, `AE02`, `AE1E`, `AE26`, `F717`, and `F722`; after normal
startup no direct writer that lowers P1.2 has yet been identified. Conversely,
the ROM does not test P1.3 directly during runtime printer service; its P1.3
bit operations are part of E80 selection.

Do not force P1.2 low or bypass `ADFF`. The next investigation should establish
the intended P1.2/MDA phase and all board-level drivers from the schematic and
E58 PAL equations, then compare it with a hardware trace or another matching
ROM revision if one becomes available.

## Reproduction

The acceptance test remains:

```sh
vt340-research/tests/mediacopy-printer.sh ./vt340
```

It intentionally fails until native target-0 SIXEL reaches E81. The bounded
known-failure regression records today's exact behavior without pretending it
is correct:

```sh
vt340-research/tests/printer-routing-known-failure.sh ./vt340
```

The trace logic is in `traces/mediacopy-printer-trace.lua`. It records native
SCN2641 accesses, XON reception, printer-ring writes, target state snapshots,
and the `ADFF`/`AE37` route.

## Closeout regression results

All members of the repository's `core` suite passed during the closeout run,
including the DC323/DC7051 device tests, boot and interprocessor checkpoints,
raster-command coverage, Set-Up entry and return, VTTEST screen features and
double-size/blink coverage, all three serial connectors, and E80 persistence.

The first aggregate run exposed two test-infrastructure issues rather than
emulator failures:

- `printer-connector` waited on a video-frame callback despite running with
  `-video none`. It now uses an emulation-time callback, a private NVRAM image,
  the already-tested checksum-preserving fast-start option, and a bounded
  20-second emulation run. The connector transport then passed in 5.58 host
  seconds.
- `setup-screen` still expected the framebuffer hash from before the recent
  display work. Two current runs produced the same new image, differing from
  the old baseline by seven lit pixels and remaining visually correct. The
  deterministic expectation was updated and the rerun passed.

Printer-specific closeout results were four passes and no failures:

| Test | Result |
| --- | --- |
| E80 EEPROM/native POST | Pass |
| SCN2641 native local-loopback diagnostic | Pass |
| External SCN2641 printer byte transport | Pass |
| Native printer-routing known-failure boundary | Pass |

The E80 persistence test also passed after two isolated boots. A final `quick`
suite run passed all seven tests, and the known-failure trace passed again
after trace-tool cleanup. Results and artifacts are retained under
`test-results/20261107T194042Z-01100e48`,
`test-results/20261107T194229Z-01100e48`,
`test-results/20261107T194333Z-01100e48`,
`test-results/20261107T194602Z-01100e48`, and
`test-results/20261107T194620Z-01100e48`.

These results demonstrate that the connector and P1.3 latch/pin separation did
not compromise POST, graphics, Set-Up, serial diagnostics, or persisted
configuration. They do not convert the target-0 media-copy route into a pass;
that behavior remains intentionally captured as the bounded known failure
described above.

## Fidelity constraints

No ROM bytes, status bits, timing delays, program-counter-qualified hardware
exceptions, expected printer bytes, or artificial success paths were added.
The only behavior changes are schematic connector wiring, endpoint defaults,
and correct separation of the P1.3 output latch from its resolved pin input.
