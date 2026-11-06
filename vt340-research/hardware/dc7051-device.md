# DC7051 driver-local timing model

## Current scope

The provisional standalone extraction has been folded back into
`src/mame/dec/vt340.cpp`. `vt340_state` owns the horizontal-output timer,
continuously running compatibility frame scheduler, diagnostic vertical
waveform, output state, event counts, and save-state registration. Keeping this
board-specific approximation local avoids presenting it as a reusable DC7051
implementation before the chip's programming interface is decoded.

This is not yet a decoded or counter-derived DC7051 model. The screen and DC323
frame-service paths use one raster definition; two other inherited waveforms
remain provisional:

| Timing path | Preserved value | Derived rate |
| --- | ---: | ---: |
| CPU2 T0 horizontal toggle | 63,000 transitions/s | 31,500 complete cycles/s |
| Screen and DC323 frame service | 32.3174 MHz / 1026 / 526 | 59.8830 Hz |
| POST diagnostic pulse | 27 us high every 16,698 us | 59.8874 Hz |

CPU2 T0 and the POST diagnostic pulse remain separate until their physical
sources and phases are known.

## Register interface and confidence

There is currently no confirmed CPU-visible DC7051 register aperture. The
earlier extraction assigned `f080-f09f` and `f0a0-f0bf` to the device and kept
two 16-entry raw arrays. Schematic sheet 17 and the native output-map loader
now prove those ranges select E51 red and E52 green/blue output maps instead;
BA4 supplies their aliases. `vt340.cpp` therefore no longer forwards these
accesses to the DC7051.

The extraction-era low/high raw arrays and accessors were removed because they
were unconnected and provided no evidence of DC7051 register organization.
Timing-load boundaries, any actual programming interface, invalid
configurations, and immediate versus latched effects all remain unresolved.

## Clock and signals

The timing model uses the board's approximately 32.3174 MHz Y1 clock.
The schematic identifies the terminal video timing nets `P2 HSYNC L` and
`P2 VSYNC H`; the extracted interface exposes only signals presently required
by established wiring:

| Interface | Direction | Current destination | Status |
| --- | --- | --- | --- |
| Y1 dot clock | input | driver-local timers | Schematic-backed source |
| horizontal timer | output | CPU2 external T0 | Preserved active-low 63 kHz toggle model; exact physical pulse width/phase unresolved |
| frame timer | event | DC323 `frame_event` | Completed-frame occurrence; deliberately has no asserted/deasserted line state |
| raster-line helper | sampled state | DC323 old/new index selector | Current line derived from the authoritative fixed frame timer; used only for the documented above/below-refresh index choice |
| diagnostic helper | sampled state | external VT340 test mux, then CPU2 P1.0 | Preserved 27 us POST waveform; physical source/mux input unresolved |

No HBLANK, VBLANK, display-enable, field, or interlace callbacks are exposed
because their physical behavior has not yet been established in this model.

## Board/device ownership

The VT340 driver owns the compatibility timing and all board integration:

- PAL aperture decoding and output-map mirroring;
- the F0E0 video-test selector;
- routing the selected diagnostic output to CPU2 P1.0;
- CPU2 and DC323 event routing;
- fixed MAME screen geometry; and
- monitor/palette/bitmap display integration.

The timing helpers remain separate from firmware addresses and terminal
protocols even though they now live in the board driver.

## Structured diagnostics

Disabled-by-default categories cover timing, synchronization, and reset.
Events include emulated time, signal, and transition/event number. Horizontal
and vertical counter fields are not fabricated because no internal counter
model exists yet.

## Remaining approximations and follow-up

1. Decode the DC7051 specification/register programming with confidence tags.
2. Identify the physical output feeding CPU2 T0 and its polarity/pulse width.
3. Decode the external F0E0 test multiplexer and map every selectable input.
4. Determine which vertical phase causes DC323 Pause Complete/Scroll Service.
5. Establish register load/latch behavior and invalid/partial programming.
6. Add HBLANK/VBLANK/display-enable only when justified by documentation.

The former `frame_enable_w` coupling was removed after a controlled A/B trace.
DC323 interrupt-enable writes had stopped and restarted the timing generator,
producing only 696 DC7051 events during 1,198 screen frames. Continuous timing
produces 1,198 events during the same interval; DC323 reset now suppresses
pre-operational frame service. See
`../traces/dc7051-continuous-frame-report.md`.

Frame service was subsequently unified with the visible screen raster. Both
now use 539,676 Y1 dot clocks per frame from the reset epoch, eliminating the
former 0.827 us-per-frame phase drift. See
`../traces/dc7051-raster-unification-report.md`.

The DC323-facing interface is explicitly event-oriented. Save/load restores
timer phase and counters and re-drives the saved horizontal level, but does not
synthesize a frame occurrence. DC323 scanline events run on the
exact 1026-dot raster cadence; they are intentionally separate from the
provisional 63 kHz external horizontal compatibility waveform so the two
clocks cannot drift at a frame boundary.

Dynamic timing and screen resolution changes remain outside this structural
extraction. Sustained VT340 smooth scrolling now verifies the fixed raster
cadence through pause coordinate 500 and progressive DC323 row movement.
