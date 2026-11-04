# DC7051 raster unification

## Scope

After frame generation was made continuous, DC7051 frame service still used
`526 / 31,500` seconds while the screen used the Y1 dot clock divided by
`1026 * 526`. The former period was 0.826721 us shorter per frame, accumulating
one complete frame of phase separation in roughly 337 seconds.

This round changed only the DC7051 frame-service period. CPU2 T0 remains the
63,000-transition/s compatibility waveform, and selector `70` retains its
27 us high pulse every 16,698 us.

## Correction

The standalone device now defines one frame as:

```text
1026 clocks/line * 526 lines = 539,676 Y1 clocks
539,676 / 32,317,400 Hz = 16.699239419 ms = 59.882966817 Hz
```

These are the same clock and totals passed to `screen_device::set_raw`. Both
timers start from the machine reset epoch. No firmware address, interrupt mask,
or host-time input affects frame phase.

## Observed phase

The synchronized trace shows the screen completion callback executes before
the DC7051 event when both are scheduled at the same timestamp. Consequently,
the first callback sees frame counter zero; every subsequent screen frame N
sees DC7051 counter N. There is no accumulating delta. At the 20-second stop,
the final DC7051 event executes after the final screen callback, producing
1,198 events for 1,198 callbacks.

The earlier screen-frame/DC7051-frame rate difference is therefore eliminated,
while callback ordering remains deterministic.

## Device regression

The firmware-free test now runs 2,000 screen-clock frames and observes:

- exactly 2,000 DC7051 frame events;
- exactly 2,104,104 transitions from the unchanged CPU2 T0 compatibility
  waveform during that interval;
- exact first-frame phase from the Y1 clock and raster totals; and
- no accumulated frame or horizontal-timer drift.

## Integration results

The following pass with the unified frame raster:

- targeted VT340 build;
- standalone DC7051 and DC323 tests;
- Phase 3 checkpoint and smoke test;
- optional fast-start path with the native result unchanged at 13.144634 s;
- original-ROM command-32 PBT;
- graphics command, frame-boundary erase, and persistent-success regression;
- native Set-Up return regression.

## Remaining work

Stage 4 subsequently made the DC323 callback an explicit event and added real
save/load plus nonzero-time reset coverage; see
`dc7051-stage4-state-report.md`. Stage 5 must identify the physical source,
polarity, width, and phase of CPU2 T0. The selector-`70` diagnostic mux also
remains provisional; neither unresolved waveform should be silently derived
from the screen merely because their nominal rates are close.
