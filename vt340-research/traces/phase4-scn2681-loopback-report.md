# SCN2681 local-loopback parity investigation

## Root cause (established before implementation)

The VT340 failure is caused by a shared MAME serial-framing bug, not missing
external loopback wiring and not a VT340 timing problem.

`device_serial_interface::transmit_register_setup` emits only the configured
number of data bits, but its odd/even parity calculation used all eight bits
of the caller's byte. CPU1 configures the SCN2681 for seven data bits and odd
parity, then writes `a6`. MAME transmits data `26` (the low seven bits), but
calculates parity from `a6`:

- `a6` contains four one bits, so the old transmitter emits parity `1`.
- The transmitted seven-bit value `26` contains three one bits, so correct odd
  parity is `0`.
- The receiver extracts `26`, checks the received `1`, and correctly declares
  a parity error.

The smallest general correction is to calculate odd/even parity from the same
configured-width data bits that are placed in the frame.

## Firmware programming sequence

Both channels receive the same diagnostic setup. Channel A uses registers
`f040-f043`; channel B uses `f048-f04b`.

| Order | Register | Value | Meaning |
| ---: | --- | ---: | --- |
| 1 | CR | `0a` | Disable transmitter and receiver |
| 2 | MR2 | `8f` | Local loopback (`MR2[7:6]=10`), CTS/RTS controls off, 2 stop bits |
| 3 | CR | `30` | Reset transmitter |
| 4 | CR | `20` | Reset receiver and empty receive FIFO |
| 5 | CR | `40` | Reset error status |
| 6 | CSR | `00` | Receiver and transmitter clock selection 0 (75 baud here) |
| 7 | CR | `10` | Reset mode-register pointer to MR1 |
| 8 | MR1 | `06` | Character-error mode, parity enabled, odd parity, 7 data bits |
| 9 | CR | `45` | Reset error status and enable transmitter and receiver |
| 10 | THR | `a6` | First diagnostic byte |

`MR1=06` decodes as `RxRTS=0`, Rx interrupt on `RxRDY`, character error mode,
parity mode `00` (with parity), parity type odd, and character length `10`
(seven bits). `MR2=8f` selects local loopback. In this mode the transmitter's
serialized output feeds the receiver internally; external TxD/RxD wiring is
irrelevant.

The firmware has additional pattern iterations, but both channels abort on
the first byte because its status contains a parity error. Therefore the
complete transmitted/received set in the failing execution is one `a6 -> 26`
frame per channel.

## Exact failing transitions

Channel A:

```text
120.482220 CR=45: SR 00 -> 0c, FIFO 0
120.482238 THR=a6: MR1=06 MR2=8f CSR=00
120.615571 receive complete: byte=26, parity_error=1, framing_error=0
120.615571 FIFO push: byte=26 errors=20, FIFO 0 -> 1, SR=25
120.673541 status read: SR=2d, FIFO 1
```

Channel B repeats the same result:

```text
120.710403 CR=45: SR 00 -> 0c, FIFO 0
120.710421 THR=a6: MR1=06 MR2=8f CSR=00
120.843754 receive complete: byte=26, parity_error=1, framing_error=0
120.843754 FIFO push: byte=26 errors=20, FIFO 0 -> 1, SR=25
120.901726 status read: SR=2d, FIFO 1
```

Parity bit `20` is first asserted in `duart_channel::rcv_complete`, when the
generic receiver reports the malformed frame. `rx_fifo_push` then attaches
the per-character error to the first FIFO entry. Since MR1 selects character
error mode, the status parity bit represents the character at the FIFO head.
The preceding `CR=45` reset-error command proves it is not stale state.

## Status bit `08`

`SR=2d` is:

- `20`: parity error (incorrect and root cause of POST failure)
- `08`: transmitter empty (expected)
- `04`: transmitter ready (expected)
- `01`: receiver ready (expected; FIFO contains one character)

Immediately after FIFO insertion, status is `25`. It becomes `2d` only after
the shift register completes and `TxEMT` is asserted. Thus bit `08` is normal
SCN2681 behavior, not a second discrepancy.

## Datasheet comparison

The Philips SCN2681 specification defines MR1's character length and parity
fields independently: parity applies to the configured five-to-eight data
bits. It defines `MR2[7:6]=10` as local loopback, in which transmitter output
is internally connected to receiver input. It also defines character error
mode as reporting parity/framing/break for the FIFO-head character, and
requires command `4x` or receiver reset to clear block errors. The firmware's
programming and expectations match those rules.

MAME's receive-side checking, FIFO association, error reset, and `TxEMT`
transition are consistent with the datasheet in this trace. Only transmit
parity generation uses the wrong data width.

## Evidence

- Firmware trace: `phase4-cpu1-comm1-diagnostic.lua`
- Device trace captured from temporary instrumentation of `mc68681.cpp`
- Firmware disassembly: channel test `432d-442b`
- Shared framing implementation: `src/emu/diserial.cpp`
- Philips Semiconductors SCN2681 product specification

## Corrected execution

After the value entering each SCN2681 transmit register was limited to the
configured character width, both channels completed the entire firmware
sweep. This driver-local form gives the unchanged shared framing layer the
same character the physical DUART accepts; the preferred upstream correction
is to limit parity generation itself. Each channel transmitted this
21-byte sequence:

```text
a6 4d 9a 35 6a d4 a9 53  a6 4d 9a 35 6a d4 a9 53  a6 4d 9a 35 6a
```

The corresponding received values, reflecting the character widths selected
by each subtest, were identical on channels A and B:

```text
26 4d 1a 35 6a 54 29 53  26 4d 1a 35 6a 54 a9 53  a6 4d 9a 35 6a
```

Before each transmit, status was `0c` (`TxEMT|TxRDY`). After every complete
local-loopback frame and before the FIFO read, status was exactly `0d`
(`TxEMT|TxRDY|RxRDY`). Every FIFO read returned the expected configured-width
value, and no status transition contained `70` error bits. Both firmware
paths reached `4340` with F0 clear and neither `4378` nor `438a` executed.

The final CPU1 POST result changed from `62` to `40`. The authentic display
now contains only `VT340 Printer Port Error - 7`; NVR, Comm 1, and Comm 2
errors are absent.

Subsequent SCN2641 work cleared the remaining printer error and changed the
aggregate result from `40` to `00`; see `phase4-scn2641-printer-report.md`.
