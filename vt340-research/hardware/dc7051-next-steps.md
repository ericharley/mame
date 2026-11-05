# DC7051 assessment and next-step plan

## Purpose

The standalone DC7051 device is a successful structural extraction of the
fixed VT340 timing behavior that previously lived in `vt340_state`. It gives
the timing generator a clear ownership boundary and provides a firmware-free
regression baseline. The extraction-era claim that `f080/f0a0` were its
firmware-visible registers has since been disproven; those ranges are the
E51/E52 output maps.

It is not yet a hardware-accurate DC7051 implementation. The current device is
a compatibility scheduler: its configured clock and register contents do not
drive its outputs, and three inherited approximations independently describe
the vertical timing. This plan defines the smallest evidence-driven path from
that compatibility model toward a coherent timing generator.

## Current implementation assessment

### Established strengths

- The device owns its retained raw state, timers, callbacks, event counters,
  diagnostics, and save-state registration.
- The VT340 driver retains board-level PAL decoding, the external video-test
  multiplexer, CPU wiring, and monitor integration.
- The device has no dependency on CPU identities, firmware addresses, ROM
  contents, or VT340-specific diagnostic selector values.
- Diagnostic logging is disabled by default and bounded when enabled.
- The firmware-free test covers reset, retained storage, inherited timing
  rates, continuous frame behavior, and long-run timer stability.

### Remaining compatibility behavior

The implementation now has one authoritative frame raster and one provisional
POST waveform:

| Path | Current definition | Effective rate |
| --- | --- | ---: |
| Screen and DC323 frame service | 32.3174 MHz / 1026 / 526 | 59.8830 Hz |
| Diagnostic waveform | 27 us high every 16,698 us | 59.8874 Hz |

The earlier compatibility frame period was approximately 0.827 us shorter than
the screen period and accumulated a full-frame phase error after roughly 337
seconds. Both frame consumers now share the screen-clock period and reset
epoch. The diagnostic pulse remains separate pending physical mux decoding.

Other unresolved behavior includes:

- The former coupling between DC323 interrupt-enable writes and the DC7051
  frame timer has been removed. A controlled trace proved that it stopped or
  rephased the raster 84 times during startup. Frame timing now runs
  continuously from reset while DC323 reset suppresses pre-operational service.
- The CPU2 T0 input receives a 31.5 kHz, 50-percent-duty square wave made from
  63,000 transitions per second. The physical signal, relevant edge, polarity,
  pulse width, and phase have not yet been established.
- The configured 32.3174 MHz device clock schedules frame service. CPU2 T0 and
  the diagnostic pulse still use compatibility constants.
- The DC323-facing callback is explicitly an event. DC323 consumes only the
  occurrence of a completed frame; no physical line level or pulse width is
  implied by this interface.
- The diagnostic waveform is derived from absolute machine time rather than a
  device or raster phase.
- Low and high raw arrays remain as unconnected extraction residue. They no
  longer have a claimed CPU aperture and should either be removed or connected
  only after an authentic DC7051 programming interface is identified.
- Save/load restores active timer phase, retained registers, counters, and the
  persistent horizontal output. A frame event is not replayed on load.

## Resolved hypothesis

The DC323 interrupt-enable/DC7051 frame-phase coupling was a scheduling flaw.
The baseline produced 696 DC7051 events over 1,198 screen frames and multiple
zero-event screen intervals after interrupt masking. With continuous timing,
all 1,198 screen frames have one DC7051 event. POST, PBT, graphics erase, Set-Up
return, and device regressions pass. The provisional rates and waveform remain
separate follow-up work.

## Planned work

### Stage 1: establish a synchronized trace baseline — complete

Add a bounded, timestamped trace that records:

- MAME screen frame and vertical-blank boundaries;
- DC7051 horizontal transitions and compatibility frame events;
- diagnostic waveform edges;
- DC323 interrupt-enable writes;
- DC323 status, interrupt, pause-complete, and scroll-service transitions;
- scroll command submission, acknowledgement, and display-list updates; and
- CPU2 interrupt entry when it can be observed without PC-dependent behavior.

Capture at least these scenarios:

1. cold boot through `VT340 OK`;
2. entering and leaving Setup;
3. ordinary terminal output with multiple full-screen scrolls;
4. sustained smooth scrolling through pause coordinate 500; and
5. a run long enough to prove the raster callback has no independent-timer
   phase drift.

The baseline deliverable is an event table identifying phase relationships at
the first DC323 enable, subsequent enable changes, and the first incorrect or
missing scroll transition.

### Stage 2: controlled interrupt-enable decoupling experiment — complete

The retained implementation runs the DC7051 raster continuously from reset.
DC323 ignores frame service while non-operational and continues to gate IRQ
delivery through its own interrupt-enable register. Horizontal rate, frame
rate, diagnostic waveform, register interpretation, and scroll logic were not
changed in this experiment.

Compare the experiment with the baseline at:

- the first DC323 interrupt-enable write;
- the first frame event following each enable-state change;
- the first pause-complete and scroll-service event;
- the first CPU execution divergence;
- POST completion and the `VT340 OK` display; and
- sustained terminal scrolling.

If continuous raster operation fixes a failure, retain it only after the trace
shows that the corrected event ordering follows physical device ownership. If
it does not, revert the experiment and preserve the trace as negative evidence.

### Stage 3: select one authoritative raster — complete

The fixed screen raster is now the interim timing authority for both visible
output and DC323 frame service. DC7051 derives the period from its configured
Y1 clock and the shared 1026-by-526 totals. The screen and device timers start
from the same reset epoch.

CPU2 T0 is intentionally unchanged because its physical source is a separate
Stage 5 question. The diagnostic waveform is also unchanged because selector
`70` has not yet been mapped to a proven DC7051 output.

Dynamic screen reconfiguration is outside this stage.

### Stage 4: correct interface and save-state semantics — complete

- Decide whether the DC323-facing frame callback represents an event or a
  physical line. Use an event callback if only an occurrence is meaningful; if
  it represents a signal, emit a documented high/low pulse.
- Add a post-load restoration path for externally visible output levels.
- Add a save/load regression covering active timing, callback state, event
  counts, register retention, and the next scheduled transitions.
- Confirm that reset at nonzero emulation time produces a defined device phase.

These changes should not alter firmware-visible timing unless a separately
measured defect requires it.

The DC323 interface is now a zero-argument event delegate named
`frame_event`; the horizontal CPU2 T0 compatibility output remains a line.
`device_post_load` re-drives only the saved horizontal level. A two-process
autosave regression checkpoints on a known low level, resumes the active
timers and counters, and reaches 2,000 total frame events without loss,
duplication, or rephasing. The same test resets the device after 2,000 frames
and proves that the first new horizontal transition and frame event use a
fresh epoch. See `../traces/dc7051-stage4-state-report.md`.

### Stage 5: identify the physical CPU2 T0 signal

Use schematics, firmware behavior, and traces to determine:

- which DC7051 or board-level signal reaches CPU2 T0;
- whether CPU2 uses rising edges, falling edges, level sampling, or pulse
  duration;
- the signal's active polarity and pulse width; and
- its phase relative to horizontal display, blanking, and sync.

Once established, replace the 50-percent square wave with the physical pulse.
Preserve a test of the edge count expected by CPU2, but do not treat the
current 63,000-transition model as proof of the waveform.

### Stage 6: identify and reconstruct the register model

Return to the schematic and board decode before tracing firmware accesses.
First identify whether the DC7051 has a CPU-visible programming interface at
all, and its actual select/address wiring. Do not reuse `f080/f0a0`: those
addresses are now proven E51/E52 output maps. If a programming path is found,
record every access with emulation time, CPU2 execution context, address,
value, prior value, and nearby accesses.

The register report should classify each conclusion as confirmed, strongly
inferred, tentative, or unknown and address:

- field widths and register pairing;
- counter preload or terminal-count values;
- horizontal and vertical totals;
- visible, blanking, and sync boundaries;
- immediate versus latched updates;
- load strobes and partial programming;
- reset values; and
- invalid or disabled configurations.

Only after this report should register writes program the raster. The final
counter-derived implementation should use the configured device clock and
drive screen timing, CPU2 timing, DC323 service events, and diagnostic outputs
from one coherent state machine.

## Regression requirements

Each behavioral change must preserve or explicitly explain:

- native firmware checksums and POST completion;
- the stable `VT340 OK` screen;
- Setup entry, exit, and NVRAM persistence;
- serial terminal operation;
- short and sustained hardware scrolling;
- repeated cold boots;
- long-run timing without accumulating phase error;
- reset from nonzero emulation time; and
- save/load continuation with no lost, duplicated, or rephased event.

Tests should validate physical relationships and firmware-visible outcomes,
not merely restate the current compatibility constants.

## Guardrails

- Do not add firmware-PC-dependent behavior.
- Do not force DC323 status bits or synthesize scroll completion.
- Do not tune pulse lengths solely to make a firmware checkpoint pass.
- Do not assign meanings to DC7051 registers without trace or documentation
  evidence.
- Change only one timing hypothesis per controlled experiment.
- Keep board-level muxing and PAL decoding out of the standalone device.
- Preserve the current implementation as a comparison baseline until the
  replacement passes the complete regression set.

## Recommended immediate work item

Proceed to Stage 5: identify the physical signal feeding CPU2 T0, including
its source, polarity, edge semantics, pulse width, and raster phase. Do not
infer that signal from the current 63,000-transition compatibility waveform
or change selector-`70` timing in the same experiment.
