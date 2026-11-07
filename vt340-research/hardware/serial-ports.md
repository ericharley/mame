# VT340 external serial and printer ports

## Implemented wiring

The SCN2681 E61 channels and SCN2641 E81 are exposed as optional MAME RS-232
slots:

| MAME slot | Controller channel | VT340 connector function |
| --- | --- | --- |
| `comm1` | A | Primary host; 25-pin RS-232 or alternate six-pin DEC-423 |
| `comm2` | B | Secondary host; six-pin DEC-423 |
| `printer` | SCN2641 E81 | Bidirectional serial printer port |

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

The printer slot follows the terminal-control-module schematic. E81 TxD drives
printer TxD, its RTS output is wired as printer DTR, and printer RxD feeds E81.
The board grounds E81's active-low CTS and DCD inputs, so those signals remain
asserted independently of the selected MAME endpoint. Printer DSR passes
through E63 to the active-low `PTRDSR L` board net and CPU1 samples it on
P1.3. The recovered printer setup uses 9600 baud, eight data bits, no parity,
and one stop bit by default.

## macOS pseudo-terminal use

Start the emulator with a pseudo-terminal attached to Comm 1:

```sh
./vt340 vt340 -rompath roms -comm1 pty -printer pty
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

Once logged into a macOS shell, source the session profile:

```sh
. vt340-research/tools/vt340-shell-compat.sh
```

It advertises `TERM=vt340`, configures an 80-column by 24-row 8N1 tty with
XON/XOFF output pacing, disables macOS `OXTABS` so horizontal-tab controls reach
the terminal unchanged, selects the ASCII `C` locale, disables automatic color
and pagers, and installs a simple prompt. Preserving tabs is required by
VTTEST's double-width alignment patterns, while output pacing is important for
large SIXEL streams. Use `VT340_TERM=vt100` before the command when deliberately
testing with the conservative text-only capability set:

```sh
VT340_TERM=vt100 . vt340-research/tools/vt340-shell-compat.sh
```

The profile saves the previous tty discipline; `vt340_restore_tty` restores
it in the same session.  All environment changes disappear normally at
logout.

### Media copy and printer capture

In the terminal's Printer Set-Up screen, select **Sixel Graphics Level 2**.
The `vt340-mediacopy` helper requests a ReGIS screen hardcopy, extracts the
terminal-generated SIXEL DCS, and restores the tty settings afterward. Start
with a small crop because a complete 800x480 hardcopy can take several
minutes:

```sh
vt340-research/tools/vt340-mediacopy --small -o mediacopy.six
vt340-research/tools/vt340-mediacopy --small --png -o mediacopy.png
```

Those commands use Media Copy to Host and receive the result through Comm 1.
The printer connector is exposed, but native firmware routing to it is still a
documented known failure. Start MAME with both PTYs and use the printer device
with the helper only when reproducing that investigation:

```sh
./vt340 vt340 -rompath roms -comm1 pty -printer pty
vt340-research/tools/vt340-mediacopy \
  --printer-device /dev/ttys011 --small -o printer-mediacopy.six
```

The actual PTY suffix varies on every run. MAME's serial-printer endpoint can
also own the eventual raw output file:

```sh
./vt340 vt340 -rompath roms -comm1 pty \
  -printer printer -printout printer-mediacopy.six
vt340-research/tools/vt340-mediacopy --printer --small
```

The second command is run inside the VT340 shell and only requests the print;
MAME owns the output file in this configuration. At present the ROM accepts
the request but does not enqueue SCN2641 bytes, so the file remains empty. See
`../PRINTER_ROUTING_REPORT.md` and the bounded
`../tests/printer-routing-known-failure.sh` regression. Do not use this route
as a working printer recipe yet. `--geometry WIDTHxHEIGHT+X+Y` selects another
screen region, while omitting it captures the complete screen.

### Dual-session Nyan Cat demo

Two text-mode animation launchers provide a visible dual-session update and
flow-control check. Each cat and its rainbow follow a repeating vertical wave.
At roughly three quarters of the journey the cat holds position while the
rainbow scrolls continuously behind it, surrounded by blinking stars. Run one
command in each logged-in session:

```sh
vt340-research/tools/nyan-left-to-right.sh
vt340-research/tools/nyan-right-to-left.sh
```

They repeat until interrupted with Ctrl-C, restore the cursor on exit, and use
terminal character shifts rather than repainting the complete display after
every frame. `NYAN_DELAY` controls the frame delay and `NYAN_LAPS` selects a
finite number of screen-width scroll cycles. In an 80-column vertical split,
limit each animation to the approximately 40 visible columns:

```sh
NYAN_COLUMNS=40 vt340-research/tools/nyan-left-to-right.sh
NYAN_COLUMNS=40 vt340-research/tools/nyan-right-to-left.sh
```

Use `NYAN_COLUMNS=66` for a 132-column session split vertically. Selecting
**Shared Update** in the terminal's General Set-Up lets both session windows
advance without giving the active session display priority.

### Animated gnuplot SIXEL

Gnuplot 6.0's `sixelgd` backend emits `DCS 9;1q` for each plot. The second
parameter requests transparent background handling on a VT340, so native
firmware preserves existing color-plane bits and successive animation frames
accumulate. The backend also inserts formatting newlines that a macOS tty
with `ONLCR` enabled expands to CR/LF inside the DCS stream.

Use the VT340 compatibility wrapper for in-place animations:

```sh
vt340-research/tools/vt340-gnuplot ./vt340_waves.gnuplot
```

The wrapper changes only the SIXEL introducer's background parameter from
transparent (`1`) to opaque (`0`) and removes formatting newlines. Native
firmware then clears the declared SIXEL extent before drawing every frame.
Ordinary static SIXEL files do not require the wrapper.

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
scrolling gaps. A native host-serial backend with modem-control forwarding
remains future work; PTYs carry the byte stream but not host modem ioctls.
