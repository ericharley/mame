# DC7051 extraction and timing-equivalence report

> Historical extraction baseline: the interrupt-enable-controlled frame timer
> described below has since been replaced by continuous frame timing. See
> `dc7051-continuous-frame-report.md` for the controlled A/B and current result.

## Pre-extraction baseline

Immediately before the DC7051 work, the complete DC323 extraction regression
passed: Phase 3 boot, CPU2 ring drain, native Set-Up rendering, external serial
connector, raster commands, and E80 persistence. The firmware-free DC323 suite
also passed.

The code-level timing baseline was:

- CPU2 T0 starts asserted and toggles every `1/63000` second.
- One full horizontal low/high cycle is `1/31500` second.
- DC323 frame service starts only after a nonzero interrupt-enable write and
  repeats every `526/31500` second (`16.698412698 ms`).
- the selector-`70` diagnostic signal is high for 27 us in a 16,698 us period;
- the screen uses 32.3174 MHz, 1026 total clocks, 526 total lines, and an
  800 by 500 visible region.

These measurements are emulated-time definitions from the working baseline,
not host wall-clock measurements.

## Extracted architecture

The new `dc7051_device` owns both 16-entry register halves, horizontal and
frame timers, output state, the diagnostic waveform, and save-state fields.
The VT340 board routes its horizontal callback to CPU2 T0 and its completed-
frame event to `dc323_device::frame_event`. The board retains F0E0 selection
and samples the device output only when selector value `70` is active. The
explicit event interface supersedes the extraction's original one-sided line
callback; see `dc7051-stage4-state-report.md`.

The fixed MAME screen and diagnostic waveform remain separate compatibility
definitions. This avoids mixing a structural extraction with an unverified
raster redesign.

## Firmware-free device results

`vt340-research/tests/dc7051-device.sh` builds a ROM-free `dc7051test` MAME
unit-test system and runs it unthrottled. It verifies:

- zero reset state for both register halves;
- low-nibble masking and decoded-index aliasing;
- full high-byte storage and aliasing;
- 27 us diagnostic high time and 16,698 us repetition;
- horizontal polarity alternation and first-event phase;
- first frame phase and periodic stability;
- stable horizontal compatibility transitions across the Y1-clock frame;
- 2,000 frames without missing or duplicate events;
- no accumulated horizontal/frame timer drift;
- real two-process save/load continuation and output restoration; and
- timing/register reinitialization from reset at nonzero emulation time.

Observed result:

```text
DC7051 firmware-free timing/save-state regression passed: 2104104 horizontal transitions, 2000 frames
```

The event count reflects the later screen-raster unification and Stage 4 state
test; the extraction-era gated frame interface is no longer present.

## VT340 verification boundary

After the timers and registers moved into the device, the complete integration
suite passed:

| Test | Result |
| --- | --- |
| Phase 3 boot checkpoint and smoke test | Pass |
| CPU2 ring drain | Pass |
| Native Set-Up screen | Pass |
| External serial connector | Pass |
| Graphics raster commands | Pass |
| E80 NVRAM persistence | Pass |

Interactive macOS login, human Set-Up navigation, jump scrolling, and the
known intermittent smooth-scroll freeze are manual checks. They are not
claimed from automated evidence.
