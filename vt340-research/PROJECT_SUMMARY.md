# VT340 MAME project summary

## Mission

This project is a ROM-level emulation of the Digital Equipment Corporation
VT340 video terminal for MAME. The goal is to run the original DEC firmware
against modeled board hardware until the terminal behaves like the physical
machine. Terminal protocols, startup messages, and graphics operations must
come from the ROMs; the driver must not replace firmware decisions with a
high-level terminal implementation.

The current driver boots both processors, passes native POST with result `00`,
exchanges CPU1/CPU2 startup handshakes, executes native graphics commands,
and displays a persistent firmware-rendered `VT340 OK` screen. It supports
Set-Up with persistent NVRAM, interactive serial sessions, text scrolling,
ReGIS, and color SIXEL. Startup still misses the fast `7ff2` checkpoint and
reaches success through the firmware's approximately 120-second timeout.

The board driver is `src/mame/dec/vt340.cpp`; the extracted Adder device is
`src/devices/video/dc323.{h,cpp}`. Research notes, disassemblies, reproduction
scripts, and tests live under `vt340-research/`.

## Architecture

```mermaid
flowchart LR
    E1[E1/E2 CPU1 ROM] --> CPU1[CPU1 control processor]
    DUART[SCN2681 host DUART] <--> CPU1
    ACIA[SCN2641 printer interface] <--> CPU1
    KBD[LK201 serial input model] --> CPU1

    CPU1 <--> RAM[64 KiB shared XDATA RAM]
    RAM <--> CPU2[CPU2 video processor]
    CPU1 <-->|DAT9 / T1 handshake| CPU2
    E3[E3 + banked E4/E5 CPU2 ROM] --> CPU2

    CPU2 --> DC7051[Standalone DC7051 timing device]
    CPU2 --> DC323[Standalone DC323 device]
    DC323 --> VIPER[Four Viper plane operations]
    E49[E49 character ROM] --> VIPER
    VIPER --> PLANES[Four 1024 x 2048 bitmap planes]
    PLANES --> PAL[16-entry 12-bit palette]
    PAL --> SCREEN[800 x 500 MAME screen]
```

### Processor and ROM organization

- CPU1 controls the terminal, serial devices, keyboard path, configuration,
  and command production. It uses the schematic-correct MAME I8031 core.
  Earlier experiments used I8032 storage to accommodate a later serial-service
  stack excursion through address `8c`; that compatibility substitution has
  been removed. The current startup path and Phase 2-4 boundary are unchanged,
  while the later stack excursion remains an open risk once startup advances.
- CPU2 performs video POST, timing work, command dispatch, and graphics setup.
  It uses the MAME I8031 core.
- Both processors run from the board's 12 MHz clock.
- The shared MCS-51 core models SBUF's direction-selected hardware latches:
  writes start transmission without overwriting the receive value returned by
  reads. This is required by CPU1's negative-loopback POST.
- CPU1 maps E1 at `0000-7fff` and E2 at `8000-ffff`.
- CPU2 maps E3 at `0000-7fff`; P3.3 selects E4 or E5 in the upper half.
- The published dumps are displaced by one byte and have a systematic page-
  transition artifact. The driver retains the raw files, reconstructs all 630
  recoverable page-final positions at initialization, and derives each missing
  checksum tail from the firmware's rotate/XOR test. The original ROM files
  are not modified; see `firmware/rom-dump-reconstruction.md`.

### Shared memory and communication

Both processors access a common 64 KiB XDATA store corresponding to E93/E94.
The first-stage model provides common storage but does not yet emulate bus
contention or arbitration delays.

Known communication mechanisms include:

- `7ff1`: CPU1/CPU2 initialization completion mailbox.
- `7ff2`: CPU1 pending sentinel and CPU2 checkpoint/final-result state.
- `7e00-7e7d`: command-ring data.
- `7e7e`: CPU1 producer index.
- `7e7f`: CPU2 consumer index.
- CPU2 P1.1 and CPU1 P3.5/T1: the bidirectional DAT9 startup handshake.
- DC323 active-low interrupt request: CPU2 INT0/frame service.

Short DAT9/T1 pulses are retained only at the firmware's known rendezvous so
they survive MAME scheduling boundaries. Controlled Phase 4 tests removed the
former perfect-quantum selection, 10 microsecond maximum quantum, and
request-specific retained pulse without changing the startup event sequence.

### CPU1 peripherals

- E61 is modeled with MAME's SCN2681 DUART and drives CPU1 INT0.  Channel A is
  exposed as the Comm 1 RS-232/DEC-423 endpoint and channel B as Comm 2; both
  accept standard MAME serial devices including a macOS pseudo-terminal.
- E81 is modeled with MAME's SCN2641 interface and drives CPU1 INT1.
- Disconnected receive inputs idle at the serial marking level.
- The keyboard uses CPU1's internal UART and MAME's ROM-driven `lk201_device`.
  CPU1 P3.1/TXD drives the keyboard receive input and the keyboard transmitter
  drives CPU1 P3.0/RXD. This replaces the former timer-generated power-on
  response.
- Reserved CPU1 SFR `c2` reads as `ff`, matching the value required by the
  firmware's formatter path.

### CPU2 video subsystem

CPU2's XDATA handler separates shared RAM from the decoded video apertures:

- DC323 Adder registers in the mirrored `f?00-f?3f` window.
- E51/E52 16-entry output maps at `f080/f0a0`, including their BA4 aliases.
- Diagnostic bitmap and graphics POST behavior.

The E15/P1 board wiring assembles each decoded Adder write and forwards it to
the standalone `dc323_device`. The device owns the 64-word register file,
status/IRQ state, command and transfer sequencing, retained Viper operation
state, frame-synchronized scrolling, and bitmap planes. Firmware-address-
independent diagnostic I/D readback, command-zero abort, and ready outputs now
live in the DC323 device. The separate bitmap-memory POST aperture and board
reset/DAT9 sequencing remain in the VT340 driver. See
`hardware/dc323-device.md`.

The standalone `dc7051_device` owns the preserved horizontal and frame timing
approximations; a line callback drives CPU2 T0 and an explicit event callback
services the DC323 at each completed frame. Frame timing
now runs continuously from reset and is independent of DC323 interrupt-enable
writes; DC323 suppresses frame service while held non-operational. The former
`f080/f0a0` register assignment was disproven by the output-map schematic and
native palette-loader trace, so no CPU-visible DC7051 register aperture is
currently claimed. The external diagnostic multiplexer and fixed screen
geometry remain board-owned. See `hardware/dc7051-device.md` and
`traces/dc7051-continuous-frame-report.md`. Save states restore the active
timer phase and persistent horizontal level without replaying a frame event;
reset at nonzero emulation time establishes a fresh timing epoch.

E80 is a CPU1-owned Xicor X2804 EEPROM. Its recovered 512-byte `23-001N2`
image supplies the first-run default for MAME's persistent X2804 device,
which is read and written through CPU1's E10-selected `f000-f1ff` aperture.
The image passes the ROM's native checksums and clears `NVR Error - 1`.
Firmware changes saved from the native Set-Up directory persist between runs
through MAME's standard NVRAM interface.

The raster path retains DC323 origins, extents, scale, mode, masks, source
selection, and Viper logic functions. It supports the proven E49-to-bitmap
and bitmap-to-bitmap normal operations used during startup. E49 is decoded
using the schematic address permutation and supplies the authentic DEC 10x20
glyphs. DC323 completion status now follows command lifecycle, and
bitmap-to-processor FIFO reads can source either E49 or ordinary off-screen
bitmap storage. This releases normal foreground processing after status-line
drawing and allows F3 to enter the original firmware's complete Set-Up
directory.

The board CNTLWR latch maps CPU2 `BAD3-BAD0` to `V0CS-V3CS` in reverse plane
order; `BAD5` is the separate `OPADDS` output. Preserving that exact wiring is
required for firmware-selected SIXEL colors. An earlier `BAD5-BAD2` decode
forced two plane bits and reduced the 16 requested indices to `3,7,11,15`.

Four 1024 x 2048 one-bit planes form a four-bit color index. The screen uses
the measured 32.3174 MHz timing: 1026 total by 526 lines, with an 800 x 500
visible area. Firmware-programmed complete palette entries display as 12-bit
RGB; entries not yet initialized after graphics POST use a monochrome
visibility fallback.

PAL E16 maps the E51 red output map at `f080/f090` and E52 green/blue at
`f0a0/f0b0`; BA4 is not decoded. E51's low nibble supplies red, while E52's
high and low nibbles supply green and blue. The recovered EEPROM validly saves
Color Map: monochrome, so native Global Set-Up must select color (and may save
it) before color SIXEL output is expected. The standard Bill regression does
this through LK201 keys and streams the fixture over the macOS-style PTY path.

### State and lifecycle

`machine_start` installs the reserved-SFR behavior, allocates timing and
keyboard timers, initializes persistent storage, registers save-state items,
and installs exit diagnostics. `machine_reset` resets all modeled latches,
registers, interrupts, serial inputs, bitmap planes, timers, and trace limits.

The driver is registered as `MACHINE_NOT_WORKING | MACHINE_NO_SOUND`. Sound
has not been investigated, and the terminal has not completed the documented
successful startup sequence.

## Engineering approach

### Evidence first

Hardware behavior is added only when supported by schematics, DEC chipset
documentation, ROM disassembly, or controlled firmware execution. Unknown
registers and signals remain explicit unknowns instead of receiving convenient
values without a firmware dependency.

### Firmware-driven behavior

The driver models inputs, registers, storage, timing, and signal semantics.
It does not manually draw startup strings, inject success packets, or branch
on program counters to declare startup complete. Graphics output is accepted
only when original firmware submits the corresponding operations.

Some PC-qualified behavior remains where the physical decode is not fully
reconstructed. These cases are documented as provisional compatibility
behavior and are not treated as final hardware models.

### ROM reconstruction standard

A damaged dump byte is reconstructed only when surrounding instruction flow,
call contracts, runtime behavior, and the ROM's own checksum constrain the
value. The reconstruction algorithm and its independently constrained
descriptor repair are documented in `firmware/rom-dump-reconstruction.md`.
This has replaced earlier synthetic continuations with native firmware
execution.

### Controlled experiments

Hypotheses are tested at the firmware decision point using bounded debugger
scripts. Experimental state changes are not compiled into the production
driver. A useful experiment must identify the expected and observed state,
change only that state, and record the resulting native execution path.

### Deterministic validation

The repository provides:

- A targeted MAME build and ROM verification procedure in `BUILDING.md`.
- A basic executable/ROM smoke test in `tests/smoke.sh`.
- A Phase 2 normal-path and controlled-handshake regression in
  `tests/phase2-closeout.sh`.
- A Phase 3 low-ROM and operational-entry checkpoint in
  `tests/phase3-checkpoint.sh`.
- A complete recoverable-ROM boundary audit in
  `tests/rom-boundary-audit.sh`.
- The current synchronization boundary in
  `traces/phase4-sync-baseline.lua`.
- Concise timestamped evidence in
  `traces/wait-to-ok/phase2-event-summary.txt`.

Large raw debugger traces and screenshots remain local generated artifacts.
Tracked Lua scripts and disassemblies make the important paths reproducible.

## Current boot path

1. CPU1 holds CPU2 in reset while it executes its ROM and board tests.
2. CPU1 releases CPU2; both processors complete their native startup and
   DAT9/T1 rendezvous paths.
3. CPU2 renders `Wait` from E49 and begins its graphics configuration.
4. CPU2 publishes the `7ff2=00` checkpoint at approximately 8.228779 s.
5. CPU1 emits its next DAT9 pulse approximately 6.898 ms later, but does not
   install pending sentinel `7ff2=10` until approximately 8.295773 s.
6. CPU1 waits for a checkpoint that CPU2 has already issued. CPU2 later
   writes the authentic `7ff2=80` result and enters operational E4 firmware.
7. CPU1's bounded checkpoint loop expires at approximately 119.955290 s,
   immediately consumes the retained `80` in its terminal-result stage, and
   enters native startup routine `4551` at approximately 119.995547 s.
8. After removal of the incorrect PC-qualified DC323 bit-0 inversion, CPU2
   drains all startup packets and CPU1 completes both `7289` passes.
9. CPU1 completes the native peripheral diagnostics and submits command 32
   with result `00` at approximately 123.960841 s.
10. CPU2 executes handler `db98`. During command 32 it issues documented PBT
    command `0bc4` and reads
    1,024 bytes of localized startup text from E49 into `cc00-cfff`.
11. Firmware submits `VT340 OK`, revision, and copyright records.
12. The frame-boundary scroll erase clears the temporary `Wait` glyph before
    the success panel, which remains visible while both processors continue.

The older command-32/ring experiment remains valid Phase 2 control-flow
evidence, but the corrected ROM baseline exposes this earlier Phase 4
sentinel/checkpoint ordering as the first fast-path timing mismatch. CPU2
never reads `7ff2`; `10` is a stale-zero guard, not a request notification.

## Known provisional or incomplete behavior

- CPU1 is back on the documented I8031 core; the previously observed later
  serial-service stack excursion above `7f` remains unresolved.
- Short DAT9/T1 handshakes use narrowly scoped pulse retention.
- The exact LK201 ROMs are connected through MAME's ROM-driven keyboard
  device; keyboard timing does not change the checkpoint mismatch.
- The 512-byte E80 `23-001N2` dump supplies the factory default. Native
  firmware writes now persist through MAME's NVRAM storage and are restored
  on later cold boots.
- DC323 register reads are no longer PC-qualified. Diagnostic `0bc0` data,
  idle completion state, FIFO readiness, and command-zero abort are generated
  by device state.
- Source-2 operations, remaining fill/non-normal raster modes, exact command
  timing, and sound are incomplete. Normal constant-source rasterops,
  frame-boundary erase, text scrolling, and the 16-entry color map work.
- Shared-memory arbitration timing is not modeled.
- DC7051 frame service is continuous and shares the screen's Y1-clock raster.
  CPU2 T0 and the provisional selector-`70` diagnostic pulse remain separate
  inherited compatibility waveforms.
- The firmware exits `Wait`; E80, both SCN2681 channels, and the SCN2641
  printer diagnostic pass, CPU1 submits POST result `00`, and the original
  `VT340 OK` panel is persistent. The unresolved startup issue is latency:
  CPU1 misses the fast checkpoint and uses the native timeout fallback.

## Repository guide

| Location | Purpose |
|---|---|
| `src/mame/dec/vt340.cpp` | VT340 board wiring, compatibility adapter, and ROM declarations |
| `src/devices/video/dc323.{h,cpp}` | Standalone DC323 register, command, IRQ, transfer, and graphics device |
| `src/devices/video/dc7051.{h,cpp}` | Standalone DC7051 raw storage and continuous compatibility timing device |
| `vt340-research/firmware/` | Disassembly findings and firmware control flow |
| `vt340-research/hardware/` | Hardware maps, video model, and open questions |
| `vt340-research/traces/` | Reproduction scripts and concise trace summaries |
| `vt340-research/tests/` | Smoke and deterministic closeout tests |
| `vt340-research/tools/` | ROM inspection and E49 decoding utilities |
| `vt340-research/SPRINT_STATUS.md` | Current sprint result and next work |
| `vt340-research/PHASE3_CLOSEOUT.md` | Completed Phase 3 evidence and Phase 4 handoff |
| `vt340-research/PHASE4_PLAN.md` | Active synchronization investigation and acceptance criteria |
