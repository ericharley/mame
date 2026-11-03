# DC7051 assessment and next-step plan

## Purpose

The standalone DC7051 device is a successful structural extraction of the
fixed VT340 timing behavior that previously lived in `vt340_state`. It gives
the timing generator a clear ownership boundary, retains the firmware-visible
register apertures, and provides a firmware-free regression baseline.

It is not yet a hardware-accurate DC7051 implementation. The current device is
a compatibility scheduler: its configured clock and register contents do not
drive its outputs, and three inherited approximations independently describe
the vertical timing. This plan defines the smallest evidence-driven path from
that compatibility model toward a coherent timing generator.

## Current implementation assessment

### Established strengths

- The device owns its raw register state, timers, callbacks, event counters,
  diagnostics, and save-state registration.
- The VT340 driver retains board-level PAL decoding, the external video-test
  multiplexer, CPU wiring, and monitor integration.
- The device has no dependency on CPU identities, firmware addresses, ROM
  contents, or VT340-specific diagnostic selector values.
- Diagnostic logging is disabled by default and bounded when enabled.
- The firmware-free test covers reset, register retention, inherited timing
  rates, enable/disable behavior, and long-run timer stability.

### Remaining compatibility behavior

The implementation presently has three independent vertical timing paths:

| Path | Current definition | Effective rate |
| --- | --- | ---: |
| DC323 frame-service event | 526 lines at 31,500 Hz | 59.8859 Hz |
| MAME screen raster | 32.3174 MHz / 1026 / 526 | 59.8830 Hz |
| Diagnostic waveform | 27 us high every 16,698 us | 59.8874 Hz |

The compatibility frame period is approximately 0.827 us shorter than the
screen frame period. Their phases separate by one screen scanline after about
38 frames and by one full frame after about 337 seconds.

Other unresolved behavior includes:

- A DC323 interrupt-enable write starts or stops the DC7051 frame timer. Each
  enable transition establishes a new raster phase, although physical video
  timing should normally continue independently of interrupt masking.
- The CPU2 T0 input receives a 31.5 kHz, 50-percent-duty square wave made from
  63,000 transitions per second. The physical signal, relevant edge, polarity,
  pulse width, and phase have not yet been established.
- The configured 32.3174 MHz device clock is not used to schedule either
  timer.
- The frame callback is declared as a line callback but emits only a high
  event and never a corresponding low state.
- The diagnostic waveform is derived from absolute machine time rather than a
  device or raster phase.
- Low and high register apertures retain data but do not affect timing. Their
  field meanings, pairing, load boundaries, and latch behavior remain unknown.
- Internal state is registered for save states, but output-line restoration
  and an actual save/load execution cycle are not covered by regression tests.

## Working hypothesis

The highest-risk scheduling flaw is the coupling between DC323 interrupt
enable and DC7051 frame phase. A physical raster should continue running while
the DC323 independently decides whether a resulting service condition may
raise an interrupt. Restarting the frame period on an interrupt-enable write
can move pause-complete or scroll-service activity relative to the visible
raster and is a plausible contributor to remaining scrolling synchronization
problems.

This is a hypothesis to test, not a justification for immediately changing
timing. The first divergence must be measured before adopting new behavior.

## Planned work

### Stage 1: establish a synchronized trace baseline

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
4. the known smooth-scroll or pause-complete failure, if reproducible; and
5. a run long enough to demonstrate the independent-timer phase drift.

The baseline deliverable is an event table identifying phase relationships at
the first DC323 enable, subsequent enable changes, and the first incorrect or
missing scroll transition.

### Stage 2: controlled interrupt-enable decoupling experiment

Run the DC7051 raster continuously from a documented reset or initialization
epoch while allowing the DC323 interrupt-enable state to gate only interrupt
delivery. Do not change the horizontal rate, frame rate, diagnostic waveform,
register interpretation, or scroll logic in the same experiment.

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

### Stage 3: select one authoritative raster

Until DC7051 register semantics are known, use one fixed-timing authority for
the screen and all raster-derived service events. Two acceptable implementation
directions are:

1. Synchronize DC7051 compatibility events to MAME screen positions. This is
   the lowest-risk interim approach because the visible raster already has a
   stable dot clock and geometry.
2. Derive the DC7051 timers from `clock()`, horizontal total, and vertical
   total, align them to a common epoch, and have the screen consume the same
   timing definition.

Do not retain separate 31,500 Hz, 16,698 us, and screen-clock epochs after this
stage. The selected approach must define reset phase, frame phase, and the
relationship between any diagnostic output and the raster.

Dynamic screen reconfiguration is outside this stage.

### Stage 4: correct interface and save-state semantics

- Decide whether the DC323-facing frame callback represents an event or a
  physical line. Use an event callback if only an occurrence is meaningful; if
  it represents a signal, emit a documented high/low pulse.
- Add a post-load restoration path for externally visible output levels.
- Add a save/load regression covering active timing, callback state, event
  counts, register retention, and the next scheduled transitions.
- Confirm that reset at nonzero emulation time produces a defined device phase.

These changes should not alter firmware-visible timing unless a separately
measured defect requires it.

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

### Stage 6: reconstruct the register model

Trace every firmware read and write to both DC7051 apertures. For each access,
record emulation time, CPU2 execution context, index, value, prior value, and
nearby accesses. Reconstruct candidate combined values without assuming that
matching low/high indexes form a register until the evidence supports it.

The register report should classify each conclusion as confirmed, strongly
inferred, tentative, or unknown and address:

- low/high field widths and pairing;
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

Implement Stage 1, then perform the isolated Stage 2 experiment. The first
decision point is whether a continuously running raster with DC323-only
interrupt gating produces the correct firmware event ordering. That result
will determine whether the next implementation task is timing unification or
further investigation of DC323 pause/scroll semantics.
