# DC323 standalone device interface

## Scope

`src/devices/video/dc323.{h,cpp}` is a structural extraction of the operational
DC323 Adder model formerly embedded in `vt340.cpp`.  Its first purpose is to
preserve the established VT340 behavior while giving the controller its own
register file, command engine, status/interrupt state, save-state ownership,
diagnostics, and frame-event input.

The extraction is not a claim that every retained behavior is confirmed
DC323 silicon behavior.  In particular, raster operations are still executed
synchronously and the retained Viper register/bitmap model remains inside the
device as a transitional graphics backend.  Viper extraction and timing
correction are separate later work.

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
| `vsync_w(state)` | Supply the board's vertical-frame event; a high call services pending scroll and frame status |
| `irq_handler()` | Electrical interrupt output, asserted when enabled sticky status is nonzero |
| `pixel_r(plane, x, y)` | Narrow display-backend access to the retained four bitmap planes |
| `bitmap_clear(data)` | Reset/diagnostic initialization of the retained bitmap storage |

The device has no CPU reference, firmware address, terminal protocol, palette,
serial port, or DC7051 timer.  The VT340 PAL continues to decode the CPU2
external address and CPU2 P1 continues to supply the high byte of every
16-bit write.

## Register and command behavior preserved

The device owns all 64 16-bit Adder register values.  Currently modeled
special registers are:

| Register | Preserved behavior |
| ---: | --- |
| `02` | Interrupt-enable mask; changes recompute IRQ |
| `03` | Operational status read and write-zero-to-clear acknowledgement |
| `07` | Retained I/D value and active bitmap/character-ROM transfer reads |
| `08` | Command decode, Viper loads, transfer setup, and raster dispatch |
| `09` | Raster X-control mode and indexed-operation qualification |
| `0e-14` | Scroll bounds, offset, and frame-pending Y command |
| `17-1a` | Indexed-operation values used by the existing zero-index qualification |
| `22-29` | Source, destination, width, and height parameters |

Status bits remain sticky until acknowledged.  Raster command functions 2 and
3 retain the existing initialization/completion/address sequencing.  A
bitmap-to-processor transfer completes through register 7 reads.  Writing
scroll register `14` records one pending operation; the next high `vsync_w`
call executes it, sets Pause Complete and Scroll Service, and recomputes IRQ.

The `bitmap_planes` memory share retains its root tag so existing debugger
traces continue to inspect exactly the same 1024 by 2048 by four-plane layout.

## Board behavior intentionally left in `vt340_state`

The following is not DC323 device behavior:

- E15 PAL selection and register mirroring;
- CPU2 P1/high-byte assembly with the low external data bus;
- F072/F060 reset and DAT9 startup sequencing;
- the separate byte-oriented bitmap POST memory and AA/55/clear sweeps;
- PC `1bd1` diagnostic I/D readback and the ready-bit observations at `2900`,
  `bba0`, `bbaa`, and `bbb4`;
- DC7051 registers and host frame-timer scheduling;
- E51/E52 palette storage and display conversion; and
- CPU2 ROM banking, shared RAM, and all serial/keyboard behavior.

The PC-qualified reads are explicitly a VT340 compatibility adapter.  They
approximate external POST mux/ready behavior that has not yet been modeled
from complete chipset timing evidence.  They must not migrate into the DC323.

## Diagnostic logging

The device defines disabled-by-default log masks for registers, commands,
scrolling, interrupts, transfers, and raster operations.  Entries use MAME
emulation time and include the relevant command parameters and status.

Scroll diagnostics record scheduling while another request is pending, frame
service, direction, distance, erase mode, exclusive bounds, Y offset, status,
interrupt enable, and IRQ transitions.  This supports investigation of the
known smooth-scroll failure without changing its behavior.  Host serial flow
control remains observable through the separate DUART/connector traces.

## Remaining hardware questions

- Exact asynchronous command completion timing and FIFO depth/flow.
- Whether the retained synchronous raster completion ordering is correct.
- Physical ownership split between Adder sequencing and each Viper's Boolean,
  mask, fill, and scroll datapaths.
- Source-2 behavior and nonzero indexed coordinate translation.
- Exact right-edge word and mask behavior when `SCROLL_X_MAX` is aligned.
- Scroll request queuing or overwrite behavior when register `14` is loaded
  more than once before a frame event.
- The physical source and phase of Pause Complete and Scroll Service.
- The real reset/ready interface currently represented by the board's
  `operational_w` transition and PC-qualified POST adapter.

These questions should be answered with chipset documentation or controlled
firmware traces after structural equivalence is secured.
