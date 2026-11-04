# DC323 assessment and next-step plan

## Purpose

The standalone DC323 device is a successful structural extraction of the
Adder model previously embedded in `vt340_state`. It owns the register file,
status and interrupt state, processor/bitmap transfer state, retained Viper
registers, raster execution, scrolling, and bitmap planes. The verified model
is sufficient for native POST, `VT340 OK`, Set-Up, terminal text, clear/erase,
and normal scrolling.

It is not yet a complete hardware model. The current implementation combines
DC323 Adder sequencing, four DC322 Viper datapaths, and one VT340-specific
display-policy heuristic. Command execution is synchronous, some status
semantics remain provisional, and several raster modes are deliberately
unsupported. This plan identifies the smallest correctness fixes and the
evidence required before expanding the graphics engine.

## Current implementation assessment

### Established strengths

- The device has a clean CPU-independent register and callback interface.
- Board PAL decoding, CPU2 bus assembly, POST control, palette hardware, and
  DC7051 timing remain in the VT340 driver.
- Status acknowledgement uses the documented write-zero-to-clear behavior.
- Interrupt output is derived from operational state, sticky status, and the
  interrupt-enable mask.
- The verified normal raster path supports E49 character-ROM sources, bitmap
  sources, constant sources, Viper masks, Boolean functions, and clipping.
- Frame-boundary erase and normal scrolling operate on all four bitmap planes,
  including the established Adder-word/Viper-edge-mask interpretation.
- Bitmap-to-processor transfers support both E49 and bitmap sources. Bitmap
  reads honor the command-selected Viper CSR's I/D-output enable when choosing
  which selected plane drives the processor bus.
- Disabled-by-default diagnostic logging is bounded for long terminal runs.
- The firmware-free device regression covers the retained core behavior and
  currently passes.

Passing the existing regression proves extraction compatibility. It does not
establish that every retained behavior matches DC323/DC322 silicon.

## Confirmed implementation defect: incomplete IRQ recomputation

The device does not recompute its interrupt output after every status change.
In particular, starting a bitmap-to-processor transfer clears command status,
sets transfer status, and may assert I/D Data Ready without calling
`update_interrupt()`. Interrupt state is updated only on a later event, such
as the final I/D read.

This can leave the electrical IRQ output inconsistent with the device's own
invariant:

```text
IRQ = operational AND ((status AND interrupt_enable) != 0)
```

### Required correction

Introduce narrow status helpers that always recompute IRQ, for example:

- `set_status(mask, reason)`;
- `clear_status(mask, reason)`; and
- `acknowledge_status(value)`.

Use them for command initialization, raster completion, PBT start and finish,
frame status, status acknowledgement, reset/operational transitions, and any
future asynchronous event. Avoid exposing mutable status to individual
command paths.

### Required focused tests

1. Enable I/D Data Ready, start a nonempty PBT, and verify immediate IRQ.
2. Consume all but the final byte and verify Data Ready remains asserted.
3. Consume the final byte and verify Data Ready clears, Address Complete sets,
   and IRQ follows the enabled mask.
4. Start a second command while completion status is enabled and verify no
   stale IRQ state survives a status clear.
5. Repeat with interrupt-enable changes before, during, and after a transfer.

## Remaining architectural issues

### Frame status generation is provisional

Each `frame_event()` call currently services a pending scroll and then sets
both Pause Complete and Scroll Service, even when no scroll is pending. This
matches the firmware path that brought the terminal into stable operation, but
the following physical semantics remain unresolved:

- whether Pause Complete is periodic or conditional on a pause request;
- whether Scroll Service is periodic, interval-controlled, or request-driven;
- whether loading the scroll register changes either event;
- whether both status bits arise on the same vertical edge; and
- how acknowledgement near an edge interacts with a newly arriving event.

These questions must be answered in conjunction with the DC7051 raster-phase
work. Changing status generation before establishing the real event ordering
could reintroduce CPU2 interrupt starvation.

### Command completion has no elapsed time

Raster operations execute inside the command-register write. Initialization,
raster completion, and address completion are therefore effectively
simultaneous. No busy state, queued command, FIFO depth, or operation overlap
is represented.

The standalone device is presently configured without an input clock. Do not
add an arbitrary delay. First establish from the schematics and Dragon
documentation:

- the physical Adder clock;
- initialization and per-pixel/per-word costs;
- which stages may overlap;
- when each completion bit changes; and
- what happens when firmware writes a command while work is active.

Once established, use device timers or a small command state machine and test
observable status transitions at intermediate times.

### VT340 display policy leaks into the device

The device sets `video_operational` when it sees an E49-to-visible-bitmap
raster operation with a 10-by-20 extent. The VT340 driver uses that inferred
state to decide whether palette writes are normal display programming or
destructive POST residue.

Recognizing a terminal character cell is not DC323 behavior. Replace this
with an explicit board-level phase derived from the existing VT340 POST state
machine. Before changing it, trace the last diagnostic palette writes and the
first operational palette writes so the replacement does not expose POST
residue or hide legitimate color-map programming.

### Overlapping bitmap copies retain a likely software-loop artifact

The raster engine always traverses top-to-bottom and left-to-right. When a
source and destination overlap, later source reads can observe pixels written
earlier in the same operation. The current test explicitly preserves this as
legacy behavior, not documented hardware behavior.

Determine how scan direction, origins, command mode, and index registers
control traversal. Add an overlap matrix covering left, right, up, and down
copies before replacing the retained behavior.

### Per-plane Viper state is modeled; device extraction remains optional

Schematic sheet 8 resolves selection: E16 decodes `f060-f07f` as `CNTLWR`,
and a 74LS174 latches CPU2 write-data bits `BAD3-BAD0` as `V0CS-V3CS`;
`BAD5` drives the separate `OPADDS` net. The
board driver now forwards that mask to four independent retained Viper
register sets. Selected planes accept direct register loads and raster writes;
the Boolean result selects each plane's foreground/background word. The
firmware-free regression verifies all 16 resulting color indices.

The remaining architectural question is whether to instantiate four DC322
subdevices. Do that only after timing, pipeline, scroll-select, and status
ownership are understood; the present per-plane state is sufficient for
functional color work without prematurely inventing a DC322 interface.

### Raster coverage is intentionally incomplete

#### Current command-coverage checkpoint (2026-11-04)

The live, test-linked version of this checkpoint is
`../tests/dc323-command-coverage.md`, generated from the canonical
`../tests/dc323-command-catalog.json`. Update that catalog and the scoped test
claims whenever implementation status changes; this narrative remains the
architectural explanation rather than the coverage authority.

The DC323 command register is a bitfield rather than a flat opcode.  Bits
`9-8` select the operation; bit `10` enables the destination, bit `11` enables
source 1, and bit `12` enables source 2.  Raster interpretation also depends
on X-control register `09`, particularly its low two mode bits.  The following
matrix describes the behavior in `dc323.cpp` as of this checkpoint:

| Command family or mode | Coverage | Current behavior / missing work |
| --- | --- | --- |
| Viper register load, `0180-019f` | Implemented | Loads the selected per-plane Viper register from the DC323 I/D register |
| Operation 2, normal mode (`X-control[1:0] = 00`), destination enabled, source 1 | Implemented | Bitmap and E49 character-ROM sources, signed vectors, scaling, clipping, masks, and Boolean functions |
| Operation 2, normal mode, destination enabled, source 1 disabled | Implemented | Uses the Viper source constant |
| Operation 2 with source 2 enabled (`S2E`, command bit 12) | Unsupported | Rejected before raster execution; source-2 selection and combination semantics remain unknown |
| Operation 2 with destination disabled | No drawing | Currently rejected; observed instances have been diagnostic forms rather than proven missing visible work |
| X-control mode `01` | Reserved | No drawing behavior should be inferred without contrary hardware evidence |
| Linear-pattern mode (`X-control[1:0] = 10`) with source 1 | Partial | Repeats a bitmap pattern using signed source/destination vectors |
| Linear-pattern mode without source 1 | Unsupported | Constant-source and other input forms are rejected |
| Fill mode (`X-control[1:0] = 11`) | Partial | Basic and baseline X/Y fills execute; equal-duration paired edges chain from retained endpoints, while independent vector expiration and crossing edges remain |
| Operation 3, source 1 enabled and destination disabled | Partial | X-mode bitmap-to-processor transfer works; exact FIFO/timing and Z mode are missing |
| Operation 3, source 1 disabled and destination enabled | Partial | X-mode processor-to-bitmap transfer works; exact FIFO/timing and Z mode are missing |
| Other operation-3 source/destination combinations | Unsupported | Ignored unless evidence establishes a defined transfer form |

Some accepted commands still have incomplete semantics:

- Hole-fill qualification no longer causes normal commands to be rejected.
  Destination-only/constant-source broad parallelograms repair holes between
  occupied scanline endpoints; source-coupled hole pixels and exact silicon
  edge cases remain unresolved.
- Normal-mode indexed commands execute only when all old/new index registers
  are zero. Nonzero indexed-coordinate translation is rejected.
- Linear-pattern mode applies the new destination index when selected, but
  source/old-index behavior and the complete index rules are missing.
- Programmable Bresenham initial/error offsets are ignored; only the currently
  reconstructed vector endpoints and steps affect traversal.
- Overlapping bitmap copies always traverse top-to-bottom and left-to-right,
  which may not match command-controlled hardware scan direction.
- PTB/PBT completion is functional but synchronous and does not reproduce the
  documented six-entry I/D FIFO occupancy or intermediate busy states.

#### Raster implementation priority

Use firmware provenance and visible/read-back effects to choose work, in this
order unless a trace establishes a different dependency:

1. **Complete fill and hole-fill behavior.** Extend the verified paired-edge
   vector strings to independent edge expiration, source-coupled hole pixels,
   crossing edges, and complement-mode corrections only as firmware traces
   constrain them. The
   current ReGIS `F(V...)` probe uses normal spans and does not validate DC323
   fill mode.
2. **Nonzero indexing and programmable raster error offsets.** These affect
   placement and oblique-vector accuracy in otherwise supported commands.
3. **Complete linear-pattern semantics.** Add constant/source selection,
   scaling, and index behavior only after identifying the firmware paths that
   request them.
4. **Source 2.** Reconstruct and implement it when a destination-enabled use
   is observed; the historical cold boot contained none.
5. **Z-mode transfers and exact FIFO/timing.** Treat functional transfer
   expansion separately from the later asynchronous command-timing work.

For each item, use `traces/dc323-command-provenance.lua` to record the emitting
PC, active descriptor handler, return stack, raw command, and X-control value.
This avoids treating POST register patterns as missing visible operations.

The historical cold-boot command inventory that motivated the current raster
work contained:

| Classification | Count | Current behavior |
| --- | ---: | --- |
| Normal mode, source 1 and destination | 1,164 | Executed |
| Normal mode, constant source and destination | 35 | Executed |
| Non-normal mode | 3,347 | Originally rejected; linear-pattern coverage has since been added |
| Destination-disabled diagnostic forms | 50 | Rejected |
| Destination-enabled source 2 | 0 | Not observed |

The large non-normal count does not by itself prove visible output is missing.
Many commands may be POST, initialization, or off-screen operations. Classify
them by mode, destination, extent, function, and visible intersection before
implementing additional behavior.

The matrix above supersedes the earlier shorthand list of unimplemented
areas. Retain these historical counts as evidence, not as a current dropped-
command count: linear-pattern support was added after the inventory was
captured, and the old classifier grouped all non-normal modes together.

### Save-state output restoration needs coverage

Internal IRQ state is saved, but there is no explicit post-load path to
re-drive the external CPU2 interrupt input. Add a save/load execution test and
restore externally visible output levels after load.

The test should cover:

- asserted and cleared IRQ;
- active PBT position and next returned byte;
- pending scroll state;
- Adder and Viper registers;
- bitmap contents; and
- correct handling of the next frame event.

## Planned work

### Stage 1: enforce status/IRQ invariants

Add the focused tests first, centralize status mutations, and fix the PBT-start
IRQ discrepancy. Record every status transition with its reason, old/new
value, enable mask, and resulting IRQ state.

Acceptance requires that the external IRQ always equals the documented
invariant immediately after every public device operation and timer event.

### Stage 2: remove the display-policy heuristic

Capture the palette/POST transition, move the operational-palette decision to
the VT340 board state, and remove `video_operational` from the generic device.
Verify identical POST and visible framebuffer hashes before and after the
change.

### Stage 3: synchronize DC323 and DC7051 event tracing

Use a common emulation-time trace for:

- DC7051 frame and vertical phase;
- DC323 Pause Complete and Scroll Service creation;
- scroll-register loads and pending state;
- DC323 status acknowledgements and IRQ transitions; and
- CPU2 interrupt entry/exit.

Trace cold boot, Setup, ordinary terminal output, repeated full-screen
scrolling, and the known smooth-scroll failure if reproducible. Establish the
first incorrect or missing event before changing frame-status semantics.

### Stage 4: add save/load output restoration

Implement post-load callback restoration and add a real save/load lifecycle
test. Keep this separate from timing changes so failures have a single cause.

### Stage 5: reconstruct command timing

Inventory firmware polling and interrupt behavior for representative command
sizes. Establish the clock and documented pipeline, then implement the
smallest asynchronous state machine that distinguishes initialization,
raster completion, address completion, and I/D readiness.

Do not introduce a command queue unless documentation or observed firmware
behavior establishes one.

### Stage 6: correct traversal and indexing

Reconstruct scan direction and indexed-coordinate rules. Replace the legacy
overlap behavior only after the directional test matrix and native graphics
regressions agree with the documented model.

### Stage 7: optionally extract the resolved Viper datapaths

Per-plane state and chip selection are now implemented inside DC323. Introduce
a standalone DC322 model only when additional documented behavior makes the
boundary useful. Preserve the existing bitmap share and display backend during
any extraction so structural work can be distinguished from new graphics
behavior.

### Stage 8: implement additional raster modes by evidence

Prioritize modes that original firmware submits to a visible or subsequently
read source region. For each added mode, document the command fields,
coordinate transformations, Viper inputs, expected pixels, and a focused
firmware-free regression.

## Regression requirements

Every behavioral change must preserve or explicitly explain:

- native checksums and full POST;
- persistent `VT340 OK` output;
- Setup entry, navigation, and NVRAM persistence;
- serial terminal operation;
- palette and visible framebuffer hashes;
- jump and sustained line scrolling;
- status-line preservation;
- repeated cold boots;
- DC323 ring-drain interrupt acknowledgement; and
- save/load continuation without duplicated, lost, or stale events.

The firmware-free suite should expand to cover PBT interrupt edges, all status
acknowledgement combinations, operational-state transitions, E49 multirow
transfers, additional bus widths, Boolean-function selection, overlapping
copies, per-plane behavior, and save/load continuation. X-mode PTB coverage
already includes the native 1 by 6 form, widths spanning multiple unaligned
bus words, edge preservation, CSR source/mask routing, and final-word status.

## Guardrails

- Do not add firmware-PC-dependent behavior to the device.
- Do not force status bits or synthesize command completion for a checkpoint.
- Do not add fixed delays without a clock and documented timing relationship.
- Do not treat compatibility tests as proof of silicon behavior.
- Do not infer a raster mode solely from its command frequency.
- Keep VT340 POST, palette policy, PAL decoding, and CPU bus assembly outside
  the standalone device.
- Change one timing or status hypothesis per controlled experiment.
- Preserve the current implementation as a comparison baseline until its
  replacement passes the complete regression set.

## Recommended immediate work item

Implement Stage 1 first: add PBT/status interrupt tests and enforce the IRQ
invariant through centralized status helpers. Then perform Stage 2 as a
separate cleanup. Coordinate Stage 3 with the DC7051 plan before changing
Pause Complete or Scroll Service generation.
