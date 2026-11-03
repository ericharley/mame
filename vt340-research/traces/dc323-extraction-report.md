# DC323 extraction equivalence report

## Baseline

The following tests were run with the pre-extraction binary on 2026-11-03:

| Test | Baseline result |
| --- | --- |
| `phase3-checkpoint.sh` | Pass, including smoke test |
| `phase4-ring-drain.sh` | Pass |
| `setup-screen.sh` | Pass |
| `serial-connectors.sh` | Pass |
| `graphics-raster-commands.sh` | Pass |
| `nvram-persistence.sh` | Pass |

This automated baseline establishes firmware boot, CPU2 packet service,
native Set-Up rendering, the external serial data path, the currently modeled
raster commands, and E80 persistence.  It does not establish every DC323
operation as hardware-correct.

Interactive macOS login, Set-Up navigation by a person, jump scrolling, and
the known smooth-scroll failure were not manually exercised during this
automated run.  They remain required manual equivalence checks and must not be
reported as passing based on the scripts above.

## Extracted architecture

The refactor adds `dc323_device` under `src/devices/video` and registers it in
`scripts/src/video.lua`.  The device now owns:

- the 64-word Adder register file;
- sticky status and interrupt masking/output;
- I/D bitmap-to-processor transfer state;
- retained Viper register values;
- raster operation execution;
- pending and frame-serviced scrolling;
- the operational bitmap planes; and
- save-state registration for migrated controller state.

`vt340_state` retains PAL/address decoding, high/low bus assembly, board POST
compatibility, DAT9, DC7051 timing, palette/display wiring, and the periodic
frame source.  No DC323 code reads a CPU program counter.

## Post-extraction verification

The targeted macOS build completed successfully with regenerated project
files and the new `dc323.cpp` object linked into `vt340`.

The complete automated baseline was then repeated against the rebuilt binary:

| Test | Extracted result |
| --- | --- |
| `phase3-checkpoint.sh` | Pass, including smoke test |
| `phase4-ring-drain.sh` | Pass |
| `setup-screen.sh` | Pass |
| `serial-connectors.sh` | Pass |
| `graphics-raster-commands.sh` | Pass |
| `nvram-persistence.sh` | Pass |

The same set can be repeated with:

```sh
vt340-research/tests/dc323-extraction.sh ./vt340
```

The existing root `:bitmap_planes` share remains available, allowing the
unchanged Set-Up, NVRAM, and raster trace scripts to validate the migrated
storage.

## Firmware-free device test

The normal MAME `mametests` target does not provide a running `device_t`
fixture. A dedicated MAME unit-test system therefore instantiates the real
DC323 device without CPUs or VT340 ROMs. It is compiled as the `dc323test`
subtarget by:

```sh
vt340-research/tests/dc323-device.sh
```

The harness directly verifies register retention/readback, status masks and
IRQ acknowledgement, all-plane constant fills, clipping, raster masks,
preserved overlapping-copy behavior, bitmap-to-processor packing, upward and
downward scrolling, aligned-word/Viper-mask handling of an unaligned logical
region, zero and saturated distance, erase mode, Y-offset wrap, repeated
pending writes, and 1,000 frame/acknowledgement cycles. Tests describe preserved
legacy behavior; passing them is not by itself proof of physical DC323
correctness.

The dedicated subtarget built successfully and printed:

```text
DC323 firmware-free device regression passed
```

## Manual follow-up procedure

1. Start the extracted build with Comm 1 attached to a PTY.
2. Log in through the VT340 using the documented macOS getty setup.
3. Source `vt340-research/tools/vt340-shell-compat.sh` on the host session.
4. Verify normal output, cursor motion, Set-Up entry/navigation, and jump
   scrolling against the pre-extraction behavior.
5. Repeat the existing smooth-scroll reproduction without changing timing or
   flow control, and collect DC323 scroll/IRQ plus DUART traces.

The known smooth-scroll defect is intentionally neither fixed nor reclassified
by this extraction.
