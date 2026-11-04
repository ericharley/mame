# DC7051 standalone timing device

## Extraction scope

`src/devices/video/dc7051.{h,cpp}` is an extraction of the timing state formerly
embedded in `vt340_state`. It owns retained raw storage, the horizontal-output
timer, continuously running compatibility frame scheduler, diagnostic vertical
waveform, output state, event counts, and save-state registration.

This first device is not yet a decoded or counter-derived DC7051 model. Unknown
registers remain raw storage. The screen and DC323 frame-service paths now use
one raster definition; two other inherited waveforms remain provisional:

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

The low/high raw accessors remain inside the standalone device only as
unconnected extraction-era storage until a separate cleanup decides whether
to remove them. They are not evidence of DC7051 register organization and
must not be used to infer timing fields. Timing-load boundaries, any actual
programming interface, invalid configurations, and immediate versus latched
effects all remain unresolved.

## Clock and signals

The device is configured with the board's approximately 32.3174 MHz Y1 clock.
The schematic identifies the terminal video timing nets `P2 HSYNC L` and
`P2 VSYNC H`; the extracted interface exposes only signals presently required
by established wiring:

| Interface | Direction | Current destination | Status |
| --- | --- | --- | --- |
| device clock | input | DC7051 | Schematic-backed Y1 source |
| `hsync_handler` | output | CPU2 external T0 | Preserved active-low 63 kHz toggle model; exact physical pulse width/phase unresolved |
| `frame_event_callback` | event output | DC323 `frame_event` | Completed-frame occurrence; deliberately has no asserted/deasserted line state |
| `diagnostic_vsync_r` | sampled output | external VT340 test mux, then CPU2 P1.0 | Preserved 27 us POST waveform; physical source/mux input unresolved |

No HBLANK, VBLANK, display-enable, field, or interlace callbacks are exposed
because their physical behavior has not yet been established in this model.

## Board/device ownership

The DC7051 owns register retention and timing scheduling. The VT340 driver
continues to own:

- PAL aperture decoding and output-map mirroring;
- the F0E0 video-test selector;
- routing the selected diagnostic output to CPU2 P1.0;
- CPU2 and DC323 wiring;
- fixed MAME screen geometry; and
- monitor/palette/bitmap display integration.

No DC7051 code references either CPU, firmware addresses, ROM data, terminal
protocols, or VT340-specific selector value `70`.

## Structured diagnostics

Disabled-by-default categories cover registers, timing, synchronization,
test-mux output, and reset. Events include emulated time, device, signal,
transition/event number, and available register context. Logging is bounded at
100,000 events so an explicitly enabled trace cannot grow without limit during
a long terminal session. Horizontal counter and vertical counter fields are
not fabricated because no internal counter model exists yet.

## Remaining approximations and follow-up

1. Decode the DC7051 specification/register programming with confidence tags.
2. Identify the physical output feeding CPU2 T0 and its polarity/pulse width.
3. Decode the external F0E0 test multiplexer and map every selectable input.
4. Determine which vertical phase causes DC323 Pause Complete/Scroll Service.
5. Establish register load/latch behavior and invalid/partial programming.
6. Add HBLANK/VBLANK/display-enable only when justified by documentation.
7. Identify whether the low/high raw arrays represent any real retained
   storage or should be removed.

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
timer phase, counters, retained registers, and re-drives the saved horizontal
level, but does not synthesize a frame occurrence. A two-process autosave test
also verifies a fresh timing epoch after reset at nonzero emulation time. See
`../traces/dc7051-stage4-state-report.md`.

Dynamic timing, screen resolution changes, and the smooth-scroll freeze are
deliberately outside this structural extraction.
