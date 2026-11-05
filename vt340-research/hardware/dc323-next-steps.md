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
display-policy heuristic. Command status and PBT FIFO service are now
asynchronous, but exact memory-arbitration timing, several complement/hole-fill
cases, and low-resolution Viper behavior remain provisional. This plan records
the remaining evidence boundaries after the functional expansion.

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

## Resolved implementation defect: incomplete IRQ recomputation

FIFO occupancy changes, timer-driven initialization/completion, transfer
completion, acknowledgement, and frame service now recompute the interrupt
output. The invariant remains:

This can leave the electrical IRQ output inconsistent with the device's own
invariant:

```text
IRQ = operational AND ((status AND interrupt_enable) != 0)
```

### Implemented correction

FIFO helpers and timer callbacks update status and immediately recompute IRQ.
A later cleanup may still centralize every mutation behind helpers such as:

- `set_status(mask, reason)`;
- `clear_status(mask, reason)`; and
- `acknowledge_status(value)`.

Use them for command initialization, raster completion, PBT start and finish,
frame status, status acknowledgement, reset/operational transitions, and any
future asynchronous event. Avoid exposing mutable status to individual
command paths.

### Remaining focused tests

1. Enable I/D Data Ready, start a nonempty PBT, and verify immediate IRQ.
2. Consume all but the final byte and verify Data Ready remains asserted.
3. Consume the final byte and verify Data Ready clears, Address Complete sets,
   and IRQ follows the enabled mask.
4. Start a second command while completion status is enabled and verify no
   stale IRQ state survives a status clear.
5. Repeat with interrupt-enable changes before, during, and after a transfer.

## Remaining architectural issues

### Frame and pause status generation

Scroll Service is generated at the frame boundary. Pause Complete is separate:
register `12` is latched for the following frame and an exact DC7051 raster
match queues the event. Two crossings may be retained, and a write-zero status
acknowledgement removes one event at a time. The sustained smooth-scroll trace
programs pause coordinate 500, just below the 480-line scroll region, and now
releases the firmware redraw at that point rather than at frame start.

The remaining boundary question is the documented suppression rule for pause
values beyond half-end-vertical when programmable DC7051 timing is modeled.

### Command timing is functional but not cycle-exact

Raster pixels are committed functionally during dispatch, but Initialization
Complete and Rasterop/Address Complete now arrive on separate four/eight
microsecond timers. PBT data crosses a six-entry FIFO with one-word asynchronous
service and visible receive/transmit back-pressure. No command queue is
invented. The standalone device remains configured without an input clock, so
the following still require schematic/trace evidence:

- the physical Adder clock;
- initialization and per-pixel/per-word costs;
- which stages may overlap;
- when each completion bit changes; and
- what happens when firmware writes a command while work is active.

Once established, replace the bounded functional intervals with the resolved
clock and arbitration costs while preserving the tested intermediate states.

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
| Operation 2 with source 2 enabled (`S2E`, command bit 12) | Partial | Source-2-only offset/tiled addressing and patterned fills execute; dual-source normal and linear commands route both reads through the selected Viper CSR bank, including external I/D-bus loads. Exact word pipeline and delay-register timing remain |
| Operation 2 with destination disabled | No drawing | Currently rejected; observed instances have been diagnostic forms rather than proven missing visible work |
| X-control mode `01` | Reserved | No drawing behavior should be inferred without contrary hardware evidence |
| Linear-pattern mode (`X-control[1:0] = 10`) with source 1 | Implemented | Applies independent fast/slow scaling, wraps the programmed pattern, retains slow position and fractional phase across destination commands, advances under pen-up, and resets on Source 1 origin loads |
| Linear-pattern mode without source 1 | Illegal/no drawing | Dragon defines the mode around source 1 and warns that unlisted command combinations are undefined; no constant-pattern behavior is invented |
| Fill mode (`X-control[1:0] = 11`) | Partial | Basic/baseline X/Y fills, unequal edge continuation, one-sided reload, and crossing reversal execute; complement-mode vertex-doubling correction remains |
| Operation 3, source 1 enabled and destination disabled | Partial | X- and Z-mode bitmap-to-processor transfers use six-word FIFO prefetch/drain; exact memory arbitration and low-resolution Z subplanes remain |
| Operation 3, source 1 disabled and destination enabled | Partial | X- and Z-mode processor-to-bitmap transfers use FIFO back-pressure and asynchronous service; exact memory arbitration and low-resolution Z subplanes remain |
| Other operation-3 source/destination combinations | Unsupported | Ignored unless evidence establishes a defined transfer form |

Some accepted commands still have incomplete semantics:

- Hole-fill qualification no longer causes normal commands to be rejected.
  Destination-only/constant-source broad parallelograms repair holes between
  occupied scanline endpoints; source-coupled hole pixels and exact silicon
  edge cases remain unresolved.
- Normal and linear-pattern commands select old/new index pairs independently
  for each enabled source and destination address using the live DC7051 raster
  line. Frame service promotes new values to old and pending values to new;
  upward bitmap movement advances behind the same raster boundary.
- Programmable signed Bresenham error offsets now initialize destination fast
  and slow vectors and fill edges B and A, respectively. Extreme overflow
  behavior has not been compared with physical silicon.
- Overlapping bitmap copies always traverse top-to-bottom and left-to-right,
  which may not match command-controlled hardware scan direction.
- PTB/PBT data uses the documented six-entry I/D FIFO with receive/transmit
  ready transitions and asynchronous one-word service. Command initialization
  and completion are timer-driven; exact contention-dependent cycle counts
  remain provisional.

#### Raster implementation priority

Use firmware provenance and visible/read-back effects to choose work, in this
order unless a trace establishes a different dependency:

1. **Complete fill and hole-fill behavior.** Unequal/crossing chained edges are
   now retained independently. Continue with source-coupled hole pixels and
   complement-mode vertex-doubling corrections only as firmware traces
   constrain them. The
   current ReGIS `F(V...)` probe uses normal spans and does not validate DC323
   fill mode.
2. **Linear-pattern silicon comparison.** Scaling, retained slow phase,
   pen-up advancement, and origin reset are implemented. Compare only exact
   sampling artifacts; do not invent behavior for the illegal source-free form.
3. **Complete source 2 timing.** Dual-source commands now perform the two
   documented Viper source cycles through either CSR bank, including local
   Source/Mask loads and cross-plane I/D-bus broadcast. Reconstruct the exact
   word-level barrel-shifter delay behavior and invalid multiple-driver case
   only when firmware or hardware evidence constrains them. Source-2-only
   patterned polygon fills use the same offset/tile addressing as normal mode.
   The historical cold boot contained no destination-enabled source-2 commands.
5. **Transfer timing refinement.** X/Z transfers and the six-entry FIFO are
   functional and asynchronous. Refine memory-arbitration-dependent cadence,
   low-resolution Z subplanes, and the inaccessible upper I/D byte separately.

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
scrolling, and sustained smooth scrolling. The November 2026 trace established
the former failure as premature Pause Complete plus an atomic bitmap move; the
corrected path now provides exact-raster pause and progressive upward movement.

### Stage 4: add save/load output restoration

Implement post-load callback restoration and add a real save/load lifecycle
test. Keep this separate from timing changes so failures have a single cause.

### Stage 5: reconstruct command timing — functional stage complete

The device now distinguishes initialization, raster completion, address
completion, receive readiness, and transmit readiness, with a six-entry FIFO.
Inventory representative command sizes and establish the physical clock before
replacing the bounded timer values with cycle-exact pipeline timing.

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
