# VT340 external serial ports

## Implemented wiring

The SCN2681 E61 channels are exposed as optional MAME RS-232 slots:

| MAME slot | SCN2681 channel | VT340 connector function |
| --- | --- | --- |
| `comm1` | A | Primary host; 25-pin RS-232 or alternate six-pin DEC-423 |
| `comm2` | B | Secondary host; six-pin DEC-423 |

The data paths connect channel-A TXD/RXD to Comm 1 and channel-B TXD/RXD to
Comm 2.  The terminal-control-module print set, schematic sheet 5, establishes
the following modem-control mapping:

| SCN2681 signal | External endpoint |
| --- | --- |
| IP0 | Comm 1 CTS |
| IP1 | Comm 1 RS-232 DSR |
| IP2 | Comm 1 speed indication |
| IP3 | Comm 1 carrier detect |
| IP4 | Comm 1 DEC-423 DSR |
| IP5 | Comm 2 DSR |
| OP0 | Comm 1 RTS |
| OP1 | Comm 1 RS-232 DTR |
| OP2 | Comm 1 speed select |
| OP7 | Comm 2 DTR |

One abstract Comm 1 endpoint represents the two alternate electrical
connectors and therefore supplies both DSR inputs.  The RS-232 DTR output is
used by the host endpoint.  Comm 1's alternate DEC-423 DTR output, electrical
line drivers, and connector-selection logic are not separately modeled.

The SCN2641 printer interface remains separate and is not exposed by this
change.

## macOS pseudo-terminal use

Start the emulator with a pseudo-terminal attached to Comm 1:

```sh
./vt340 vt340 -rompath roms -comm1 pty
```

Open MAME's **Pseudo Terminals** information menu to find the assigned macOS
slave device, for example `/dev/ttys005`.  Configure the PTY attachment to
match the terminal's active communication setup.  The recovered E80 startup
configuration produces Comm 1 at 19200 baud and Comm 2 at 9600 baud; both use
eight data bits, no parity, one stop bit, and no flow control.  The matching
MAME endpoint defaults are applied automatically.

For a first interactive check, attach a host program such as `screen` to that
slave device.  A host shell or a physical `/dev/cu.usbserial-*` adapter can be
connected through a byte-stream bridge such as `socat`.  PTY bridging carries
characters but does not propagate host modem-control ioctls, so use software
or no flow control for that limited configuration.

Once logged into a macOS shell, source the conservative session profile:

```sh
. vt340-research/tools/vt340-shell-compat.sh
```

It advertises `TERM=vt100`, configures an 80-column by 24-row 8N1 tty with no
software flow control, selects the ASCII `C` locale, disables automatic color
and pagers, and installs a simple prompt.  These settings reduce unrelated
host escape sequences while testing the terminal.  The terminal itself may
remain configured as a VT340.  Use `VT340_TERM=vt220` before the command only
when deliberately testing the larger VT200 capability set:

```sh
VT340_TERM=vt220 . vt340-research/tools/vt340-shell-compat.sh
```

The profile saves the previous tty discipline; `vt340_restore_tty` restores
it in the same session.  All environment changes disappear normally at
logout.

The port slot also accepts MAME's `loopback`, `null_modem`, `terminal`, and
other standard RS-232 endpoint devices.  Comm 2 is selected with `-comm2` in
the same way.

A controlled Comm 1 PTY run verified the complete path in both directions.
macOS supplied `HI` through the PTY, CPU1 received bytes `48 49 0D`, the native
firmware passed them through its receive queue and CPU1/CPU2 video ring, and
the display rendered `HI` at the home position.  Posting `a` through the
ROM-driven LK201 produced byte `61` in the SCN2681 transmit register.  The
observation script is `../traces/serial-connector-trace.lua`.

## Current boundary

This wiring exposes the original firmware and DUART, not a high-level terminal
protocol implementation.  Basic text interaction can therefore reveal
remaining display-controller, raster-operation, character-attribute, or
scrolling gaps.  The printer connector and a native host-serial backend with
modem-control forwarding remain future work.
