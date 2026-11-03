# DC7051 extraction and timing-equivalence report

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
The VT340 board routes its horizontal callback to CPU2 T0 and its frame callback
to `dc323_device::vsync_w`. The board retains F0E0 selection and samples the
device output only when selector value `70` is active.

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
- exactly 1,052 horizontal transitions per compatibility frame;
- 2,000 frames without missing or duplicate events;
- no accumulated horizontal/frame timer drift;
- clean frame disable; and
- timing/register reinitialization on reset.

Observed result:

```text
DC7051 firmware-free timing regression passed: 2104000 horizontal transitions, 2000 frames
```

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
