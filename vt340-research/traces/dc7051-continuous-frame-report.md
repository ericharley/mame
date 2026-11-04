# DC7051 continuous-frame experiment

## Question

The extracted DC7051 frame timer was controlled by DC323 interrupt-enable
writes. This gave an unrelated interrupt mask the ability to stop the video
timing generator and establish a new frame phase. The controlled experiment
tested continuous DC7051 timing while leaving all rates, the provisional POST
waveform, screen geometry, and scroll implementation unchanged.

## Trace method

`dc7051-sync-trace.lua` correlates:

- MAME screen frame completion;
- the DC7051 saved frame-event counter;
- DC323 status;
- DC323 interrupt-enable and status-acknowledge writes;
- scroll requests; and
- F0E0 diagnostic-selector writes.

It is read-only and does not inspect firmware PCs to manufacture device state.
Both sides of the A/B used the optional fast-start configuration solely to
shorten the trace; the original-ROM timeout path was tested separately.

## First divergence and result

The old implementation generated no DC7051 frames until a nonzero DC323
interrupt-enable write. Later zero writes stopped it again. At 13.209098 s,
screen frame 790 completed with `device_delta=0`; the same remained true for
the following frames until firmware re-enabled the DC323 interrupt.

| 20-second trace | Old coupling | Continuous timing |
|---|---:|---:|
| Screen frames observed | 1,198 | 1,198 |
| DC7051 frame events | 696 | 1,198 |
| DC323 interrupt-enable writes | 84 | 84 |
| DC323 status acknowledgements | 1,079 | 1,085 |
| Scroll requests | 4 | 4 |

With continuous timing, every screen callback observed exactly one new DC7051
frame event. The DC7051 frame counter is no longer reset, stopped, or rephased
by any of the 84 DC323 interrupt-enable writes.

## Retained correction

- DC7051 starts its compatibility frame timer at device reset and leaves it
  running.
- The board driver no longer forwards DC323 interrupt-enable writes into the
  timing generator.
- DC323 ignores frame events while reset/non-operational, preventing stale
  Pause Complete or Scroll Service state before board release.

This separates timing generation, DC323 status latching, and interrupt masking
along their device ownership boundaries.

## Verification

Passing checks after the correction:

- standalone DC7051 2,000-frame timing regression;
- standalone DC323 reset/frame-service regression;
- Phase 3 checkpoint;
- optional fast-start path, with native result arriving at 13.144662 s;
- original-ROM timeout path and 1,024-byte command-32 PBT;
- graphics command, frame-boundary erase, and persistent-success regression;
- native Set-Up entry/return regression.

The original-ROM PBT completes at 123.976399 s with the expected startup bytes.

## Remaining boundary

At the end of this experiment, frame service still used `526 / 31,500` while
the screen used the 32.3174 MHz raw raster. Stage 3 subsequently unified those
paths; see `dc7051-raster-unification-report.md`. CPU2 T0 and the 27 us/16,698
us diagnostic waveform remain separate because their physical sources are not
yet established.
