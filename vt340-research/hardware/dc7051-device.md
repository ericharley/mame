# DC7051 standalone timing device

## Extraction scope

`src/devices/video/dc7051.{h,cpp}` is a behavior-preserving extraction of the
timing state formerly embedded in `vt340_state`. It owns the two raw register
halves, horizontal-output timer, compatibility frame scheduler, diagnostic
vertical waveform, output state, event counts, and save-state registration.

This first device is not yet a decoded or counter-derived DC7051 model. Unknown
registers remain raw storage, and the three inherited timing definitions are
preserved rather than silently unified:

| Timing path | Preserved value | Derived rate |
| --- | ---: | ---: |
| CPU2 T0 horizontal toggle | 63,000 transitions/s | 31,500 complete cycles/s |
| DC323 compatibility frame event | 526 / 31,500 s | 59.8859 Hz |
| MAME screen raster | 32.3174 MHz / 1026 / 526 | 59.8830 Hz |
| POST diagnostic pulse | 27 us high every 16,698 us | 59.8874 Hz |

The small differences are pre-existing approximations. Combining them is
deferred until the register definitions and physical signal phases are known.

## Register interface and confidence

The VT340 E15/PAL board decode remains in `vt340.cpp`. It reduces the CPU2
address to one of two device calls:

| CPU2 aperture | Device interface | Preserved storage | Confidence |
| --- | --- | --- | --- |
| `f080-f09f` | `low_r/low_w(index)` | low four bits in one of 16 bytes | Confirmed existing behavior; physical internal organization unresolved |
| `f0a0-f0bf` | `high_r/high_w(index)` | all eight bits in one of 16 bytes | Confirmed existing behavior; physical internal organization unresolved |

Address bit 4 aliases within each 32-byte board aperture, while the device sees
only `index[3:0]`. All 16 low and 16 high reset values are zero in the preserved
model. No functional meaning is assigned to any register field yet. Writes do
not alter timing because the previous driver also retained them without
decoding them.

Evidence classifications:

- The two apertures and aliases are established by current PAL/address-decode
  work and native firmware accesses.
- The low-nibble versus full-byte bus behavior is established by the existing
  implementation and round-trip POST behavior.
- The relationship between corresponding low/high locations and a wider
  physical register is unresolved.
- Timing-load boundaries, invalid configurations, and immediate versus latched
  programming effects are unresolved.

## Clock and signals

The device is configured with the board's approximately 32.3174 MHz Y1 clock.
The schematic identifies the terminal video timing nets `P2 HSYNC L` and
`P2 VSYNC H`; the extracted interface exposes only signals presently required
by established wiring:

| Interface | Direction | Current destination | Status |
| --- | --- | --- | --- |
| device clock | input | DC7051 | Schematic-backed Y1 source |
| `hsync_handler` | output | CPU2 external T0 | Preserved active-low 63 kHz toggle model; exact physical pulse width/phase unresolved |
| `frame_handler` | event output | DC323 `vsync_w` | Compatibility frame service, not asserted to be a literal VSYNC pin |
| `diagnostic_vsync_r` | sampled output | external VT340 test mux, then CPU2 P1.0 | Preserved 27 us POST waveform; physical source/mux input unresolved |
| `frame_enable_w` | compatibility input | driven from DC323 interrupt-enable writes | Not assigned to a documented DC7051 pin |

No HBLANK, VBLANK, display-enable, field, or interlace callbacks are exposed
because their physical behavior has not yet been established in this model.

## Board/device ownership

The DC7051 owns register retention and timing scheduling. The VT340 driver
continues to own:

- PAL aperture decoding and mirroring;
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
5. Replace `frame_enable_w` coupling with continuously generated physical
   timing after proving firmware equivalence.
6. Select one authoritative raster: preferably a DC7051 counter model driving
   callbacks and screen configuration, or a screen-synchronized equivalent.
7. Establish register load/latch behavior and invalid/partial programming.
8. Add HBLANK/VBLANK/display-enable only when justified by documentation.
9. Add a save/load execution test once the device-test harness gains a safe
   programmatic state-file lifecycle.

Dynamic timing, screen resolution changes, and the smooth-scroll freeze are
deliberately outside this structural extraction.
