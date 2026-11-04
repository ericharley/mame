# DC7051 Stage 4 interface and state semantics

## Scope

Stage 4 resolves the meaning of the DC7051-to-DC323 frame interface and tests
state continuation and reset phase. It does not change the frame rate, CPU2 T0
compatibility waveform, diagnostic selector waveform, or firmware behavior.

## Interface decision

The DC323 consumer reacts to the occurrence of a completed frame. It does not
sample an asserted level, observe a falling edge, or depend on pulse width.
The interface is therefore a zero-argument `frame_event` delegate rather than
a line callback. DC323 ignores the event while non-operational and applies its
own interrupt-enable semantics after it becomes operational.

CPU2 T0 remains a distinct line callback because the processor observes a
level/edge waveform. Its physical source and shape remain Stage 5 work.

## Post-load behavior

The scheduler restores the two active timers and their remaining time. The
device's saved state restores raw retained storage, the horizontal level,
transition count, and frame-event count. `device_post_load` then re-drives the
saved horizontal level so downstream devices do not retain their reset-time
level. It deliberately does not emit a frame event: loading a state is not a
new raster boundary.

The post-load line callback is treated by the regression harness as level
restoration rather than as another horizontal transition.

## Regression method and result

`tests/dc7051-device.sh` performs an actual two-process MAME autosave cycle:

1. The first process runs to 100 frame periods plus 1 microsecond, verifies
   that horizontal output is low, and exits so MAME writes an automatic state.
2. A new process starts from reset, automatically loads that state, and
   verifies that exactly one device post-load occurs and restores the low
   output.
3. Execution continues to 2,000 total frame events. The test observes exactly
   2,104,104 horizontal transitions and 2,000 frame events, with exact first
   phases and no accumulated timer drift.
4. At that nonzero emulation time, the harness resets the DC7051. Registers,
   counters, and horizontal output return to reset state. The first subsequent
   frame event occurs exactly one 539,676-dot-clock period after reset, and the
   horizontal counter matches a newly established epoch.

The focused regression passes. The full VT340 regressions listed in the Stage
4 closeout were then rerun to ensure that changing the callback type and state
restoration semantics did not change firmware-visible behavior.

## Integration closeout

The following all pass with the Stage 4 implementation:

- targeted VT340 build;
- standalone DC7051 save/load/reset regression;
- standalone DC323 regression;
- Phase 3 native startup checkpoint and smoke test;
- optional fast-start native-result regression;
- original-ROM command-32 bitmap-to-processor transfer;
- graphics command, frame-boundary erase, and persistent-success regression;
- native Set-Up return regression.

## Remaining boundary

Stage 5 must identify the real DC7051 or board signal feeding CPU2 T0 and its
polarity, edge, pulse width, and raster phase. The current 63,000-transition
square wave is still compatibility behavior and is not evidence of the
physical waveform.
