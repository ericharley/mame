# DC323 standalone device interface

## Scope

`src/devices/video/dc323.{h,cpp}` is a structural extraction of the operational
DC323 Adder model formerly embedded in `vt340.cpp`.  Its first purpose is to
preserve the established VT340 behavior while giving the controller its own
register file, command engine, status/interrupt state, save-state ownership,
diagnostics, and frame-event input.

The extraction is not a claim that every retained behavior is confirmed
DC323 silicon behavior. Raster pixels are still committed functionally during
command dispatch, while externally visible initialization/completion status
and PBT FIFO service advance on emulation-time timers. The retained Viper
register/bitmap model remains inside the device as a transitional graphics
backend; Viper extraction and exact arbitration timing are separate later work.

## External interface

The board configures the device with:

- a character-generator ROM region;
- a bitmap memory-share tag; and
- an IRQ callback wired to CPU2 INT0.

The runtime interface is:

| Interface | Meaning |
| --- | --- |
| `read(offset)` | Read one of the 64 decoded DC323 registers or the active I/D transfer port |
| `write(offset, data)` | Write a decoded register with the board-assembled 16-bit data value |
| `operational_w(state)` | Release or hold the operational model around board graphics POST |
| `viper_select_w(mask)` | Select which of the four plane datapaths accept Viper loads and raster destination writes |
| `frame_event()` | Supply one completed-frame occurrence; services pending scroll and frame status without implying a physical line level |
| `scanline_event(line)` | Supply the current DC7051 device-coordinate raster for progressive scroll movement and pause comparison |
| `irq_handler()` | Electrical interrupt output, asserted when enabled sticky status is nonzero |
| `pixel_r(plane, x, y)` | Narrow display-backend access to the retained four bitmap planes |
| `bitmap_clear(data)` | Reset/diagnostic initialization of the retained bitmap storage |

The device has no CPU reference, firmware address, terminal protocol, palette,
serial port, or DC7051 timer.  The VT340 PAL continues to decode the CPU2
external address and CPU2 P1 continues to supply the high byte of every
16-bit write. The board also decodes `f060-f07f` as `CNTLWR`; its 74LS174
latches `BAD3-BAD0` as `V0CS-V3CS` and forwards that mask to
`viper_select_w`. `BAD5` on the same latch drives the separate `OPADDS` net.

## Register and command behavior preserved

The device owns all 64 16-bit Adder register values.  Currently modeled
special registers are:

| Register | Preserved behavior |
| ---: | --- |
| `02` | Interrupt-enable mask; changes recompute IRQ |
| `03` | Operational status read and write-zero-to-clear acknowledgement |
| `07` | Retained I/D value and active bitmap/character-ROM transfer reads |
| `08` | Command decode, selected-Viper loads, transfer setup, and raster dispatch |
| `09` | Raster X-control mode and independent source/destination indexing |
| `0e-14` | Scroll bounds, double-buffered pause coordinate, offset, and frame-pending Y command |
| `15-1a` | Pending, new, and old X/Y index values and frame-boundary promotion |
| `22-29` | Source, destination, width, and height parameters |
| `2c-2e` | Source-2 origin and power-of-two tile dimensions |
| `2f-30` | Signed Bresenham error adjustments for the two vector generators |

Status bits remain sticky until acknowledged.  Raster command functions 2 and
3 retain the existing initialization/completion/address sequencing.  A
bitmap-to-processor transfer completes through register 7 reads.  Bitmap
source data comes from the selected Viper plane whose command-selected CSR
enables I/D-bus output; it is not inherently sourced from plane zero.  Writing
scroll register `14` records one pending operation. The next `frame_event`
starts it and sets Scroll Service; subsequent scanline events move upward-scroll
rows behind refresh. Pause Complete is independently generated when refresh
equals the frame-latched register `12` coordinate and retains a two-event queue.

X-mode processor-to-bitmap commands consume one I/D word per bitmap bus word
and scanline. Each word is routed through the command-selected CSR external
load field to the Viper source or mask registers before the destination
read-modify-write cycle. Unaligned rectangles consume their leading and
trailing bus words while edge masking preserves pixels outside the extent;
Address Complete is asserted after the final expected word. The processor side
now uses the documented six-entry FIFO: transmit-ready falls at six queued
words, bitmap service consumes entries asynchronously, and cancel clears the
queue. Bitmap-to-processor commands prefetch into the same queue, assert
receive-ready while it is nonempty, and defer Address Complete until the last
prefetched word is read.

Z-mode transfers consume one I/D word per pixel. Each selected Viper's plane
address chooses its bit in the word and its two high address bits select the Z
block. PTBZ implicitly loads the command-selected foreground or background
register before the function-2 destination write; BTPZ packs the selected
bitmap planes back into their addressed word bits. The VT340 processor exposes
only the low I/D byte, and low-resolution Viper subplane expansion remains a
separate fidelity boundary.

Each of the four planes now retains its own Viper registers. A raster logic
result selects that plane's foreground or background word; the selected bit
from that word becomes the plane output. This is sufficient to form all 16
four-plane color-map indices without inventing RGB values.

Normal and linear-pattern raster destinations use both signed fast and slow
vectors. Each vector follows the documented Bresenham initialization and
selects its origin through, but not including, its endpoint. This supports
rotated ReGIS vectors, text cells, and circle spans without protocol-specific
rendering. Raster mode selection uses mode-register bits 0-1; hole-fill bit 4
does not incorrectly reclassify normal mode as unsupported.

Linear-pattern mode applies the ordinary fast and slow scale accumulators to
the independently programmed source pattern. Fast scale and pattern position
restart for every destination fast vector. Source slow position and fractional
slow-scale phase survive subsequent destination commands, including pen-up
commands, until either Source 1 origin component is loaded. Source vectors wrap
at their programmed signed extents.

Normal and linear-pattern source and destination addresses independently honor
the X-control indexing enables. At a frame boundary, the previous new pair
becomes old and the pending pair becomes new. During a scrolling frame, each
address above the live DC7051 raster boundary uses the new pair and each
address below it uses the old pair; outside a pending transition the new pair
applies throughout. Upward bitmap movement follows the same scanline boundary,
so redraws use the new indexes only after the corresponding rows have moved.
Downward movement retains reverse-order copying to preserve overlapping data.

Normal-mode source-2-only rasters derive their source address from the
unindexed destination address plus the source-2 origin. With tiling enabled,
only the destination bits selected by the programmed power-of-two width and
height participate, so the pattern remains phase-aligned across independently
drawn objects. Destination indexing moves the write without moving the tile
phase. The same source-2 addressing textures ordinary and baseline polygon
fill spans, including chained fills supported by the retained edge state.

When both bitmap sources are enabled, the two reads are separate Viper source
cycles rather than a fixed Boolean combination. Command bit 2 selects CSR
bank 0/1/2 or 4/5/6 for source 1, source 2, and destination respectively. For
each source cycle, CSR bits 3-2 load the local read into Source, both masks, or
Mask 2; bits 1-0 select the same targets for a value driven on the shared I/D
bus; and bit 4 enables that Viper's shifted local read onto the bus. The model
applies these routes per selected plane before the ordinary logic-unit write.
This supports local Source/Mask routing, either CSR bank, cross-plane I/D-bus
broadcast, and the same routing in normal and linear-pattern modes.

The two programmable error registers offset Bresenham initialization from its
normal negative major-axis magnitude. `ERR1` controls the destination slow
vector and fill edge A; `ERR2` controls the destination fast vector and fill
edge B. The same mapping applies to linear-pattern destinations. This permits
firmware to shift the center line of an oblique vector without changing its
slope or endpoints.

Fill mode `11` now has bounded functional coverage. Basic X/Y two-edge fills
use the destination slow generator as edge A and the source-1 generator as
edge B, while baseline mode locks edge B to the applicable source origin.
Each ordinary edge retains its own vector origin, Bresenham error adjustment,
and progress. When one edge expires, firmware may load only that side and the
other resumes from its partial vector; crossing edges reverse the fast scan
without terminating the chain. A destination-origin load or fill-mode change
starts a new string.
Destination-only broad parallelograms with hole-fill enabled retain their
ordinary writes and add missing pixels between occupied scanline endpoints.
The implementation deliberately does not infer source pixels for added holes,
or correct complement-mode vertex doubling.
See `../traces/dc323-fill-report.md` for the evidence boundary and tests.

The `bitmap_planes` memory share retains its root tag so existing debugger
traces continue to inspect exactly the same 1024 by 2048 by four-plane layout.

## Board behavior intentionally left in `vt340_state`

The following is not DC323 device behavior:

- E15 PAL selection and register mirroring;
- CPU2 P1/high-byte assembly with the low external data bus;
- F072/F060 reset and DAT9 startup sequencing;
- the separate byte-oriented bitmap POST memory and AA/55/clear sweeps;
- DC7051 registers and host frame-timer scheduling;
- E51/E52 palette storage and display conversion; and
- CPU2 ROM banking, shared RAM, and all serial/keyboard behavior.

Diagnostic I/D readback and ready status are device-owned and independent of
firmware addresses. The DC323 retains diagnostic selectors `00cf`/`00c6`,
routes command `0bc0` through the six-entry FIFO completion path, initializes
idle completion outputs when made operational, and returns to idle on command
zero. Raster/PBT initialization and completion status are delivered by
separate emulation-time timers rather than being asserted in the command
write. See `../traces/dc323-post-shim-cleanup-report.md`.

## Diagnostic logging

The device defines disabled-by-default log masks for registers, commands,
scrolling, interrupts, transfers, and raster operations.  Entries use MAME
emulation time and include the relevant command parameters and status.

Scroll diagnostics record scheduling while another request is pending, frame
service, direction, distance, erase mode, exclusive bounds, Y offset, status,
interrupt enable, pause coordinate, and IRQ transitions. This supports the
verified two-pixel smooth-scroll workload. Host serial flow
control remains observable through the separate DUART/connector traces.

## Remaining hardware questions

- Exact memory-arbitration-dependent command duration; initialization,
  completion, one-microsecond PBT service, and six-word flow control are now
  asynchronous but use bounded functional timing.
- Whether the four retained per-plane Viper datapaths should become standalone
  DC322 subdevices after their remaining timing and pipeline behavior is known.
- Exact word-level Viper barrel-shifter/delay-register behavior and electrical
  contention when more than one selected Viper drives the I/D bus.
- Low-resolution Viper subplane behavior during Z-mode transfers.
- Exact right-edge word and mask behavior when `SCROLL_X_MAX` is aligned.
- Scroll request queuing or overwrite behavior when register `14` is loaded
  more than once before a frame event.
- Exact half-end-vertical suppression of out-of-range pause coordinates.
- The exact physical reset input currently represented by the board's
  `operational_w` transition.

These questions should be answered with chipset documentation or controlled
firmware traces after structural equivalence is secured.
