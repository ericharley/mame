# DEC VT340 ROM-level emulator research preview

This directory contains the driver documentation, repeatable tests, fixtures,
and hardware research for the experimental MAME VT340 implementation in
`src/mame/dec/vt340.cpp`. Assertions are classified as confirmed, inferred,
or unresolved. The original ROM binaries are intentionally excluded from Git.

## Current status

This is an alpha-quality research preview, not an upstream-ready MAME driver.
The original firmware completes POST and displays `VT340 OK`. Text terminal
operation, Set-Up and NVRAM persistence, serial PTY access, hardware scrolling,
ReGIS, and 16-color SIXEL are usable. The driver remains correctly marked
`MACHINE_NOT_WORKING` because some raster modes, exact DC323/DC7051 timing,
sound, and two narrowly scoped startup compatibility paths remain unresolved.

The unmodified firmware normally takes approximately 120 seconds to pass a
missed startup checkpoint. An optional, documented configuration skips that
checkpoint while still waiting for and validating the firmware's native POST
result. See `firmware/fast-start-patch.md`.

ROMs are copyrighted data and are not distributed here. Versioned set and
profile metadata, hashes, provenance, and the local-library workflow are in
`roms/`; the binary images remain under the ignored top-level `roms/` tree.
See `BUILDING.md` for activation and verification commands.

## Gallery

See [`gallery/README.md`](gallery/README.md) for native cold-boot animation,
the `VT340 OK` and Set-Up screens, full-color SIXEL output, ReGIS examples,
and focused graphics-conformance scenes. Every tracked image is tied to a
passing regression or reproducible capture script.

## Quick start

From the MAME checkout root:

```sh
make -j4 REGENIE=1 USE_LIBSDL=1 \
  SUBTARGET=vt340 \
  SOURCES=src/mame/dec/vt340.cpp,src/mame/dec/lk201.cpp \
  MACHINES='68681,SCN_PCI,EEPROMDEV'
./vt340 -verifyroms vt340 -rompath roms
./vt340 vt340 -rompath roms -comm1 pty
```

See `BUILDING.md` for prerequisites and targeted builds,
`hardware/serial-ports.md` for PTY use, and `tests/README.md` for the common
manifest-driven regression and evidence system. The optional WebAssembly
frontend is documented in `browser/README.md`.

Primary evidence:

- DEC drawing set `K-TC-VT340_Schematic_Feb87.pdf`, especially terminal
  control module sheets on scanned PDF pages 18-27.
- Malcolm Macleod's VT340 Internals archive and its buzzed-out cartridge
  wiring table.
- DEC `EK-VT340-PS-002` Pocket Service Guide.
- Intel order 270499-006, the 8031AH/8032AH family data sheet.
- The ROM images themselves.

The exact MAME checkout used for this sprint is commit
`39eb9e44c394df9aec8186f2d2ef7517ace232e1`.

## Project guide

- `PROJECT_SUMMARY.md` describes the current architecture and engineering
  approach.
- `SPRINT_STATUS.md` records the successful `Wait` to `VT340 OK` path, tests,
  remaining fast-start blocker, and recommended next work.
- `PHASE3_CLOSEOUT.md` records the completed dispatcher and execution-integrity
  audit.
- `PHASE4_PLAN.md` defines the active `7ff2` fast-path synchronization
  investigation and separates it from the completed functional boot path.
- `traces/phase4-clock-ratio-summary.txt` and
  `traces/phase4-initial-pulse-retention-summary.txt` record the latest
  rejected clock-skew hypothesis and the newly bounded startup phasing issue.
- `UPSTREAM_MAME_WORK.md` separates reusable serial-device and CPU-core
  corrections from VT340-specific work and defines focused upstream tasks.
- `hardware/serial-ports.md` documents Comm 1/Comm 2 wiring, macOS PTY use,
  and the host-shell compatibility profile.
- `hardware/dc323-device.md` documents the extracted Adder interface,
  ownership boundary, diagnostics, and unresolved hardware questions.
- `hardware/dc7051-device.md` documents the extracted timing-generator
  interface, corrected register-ownership boundary, signal routing, and
  retained approximations.
- `traces/sixel-color-report.md` documents the native Color Map decision,
  corrected E51/E52 decode, and full PTY-driven color SIXEL result.
- `traces/dc323-extraction-report.md` records before/after equivalence and
  firmware-free device-test results.
- `traces/dc7051-extraction-report.md` records timing measurements,
  firmware-free test results, and VT340 verification boundaries.
- `traces/dc7051-continuous-frame-report.md` records the controlled removal of
  DC323 interrupt-mask control over DC7051 frame phase.
- `traces/dc7051-raster-unification-report.md` records the screen-clock frame
  unification and long-run phase result.
- `traces/dc7051-stage4-state-report.md` records the explicit frame-event
  interface, real save/load continuation, output restoration, and nonzero-time
  reset results.
- `BUILDING.md` contains the targeted build and debugger procedure.
- `roms/catalog.json` and `roms/sets/` describe versioned terminal and keyboard
  firmware sets without tracking the copyrighted binaries; `roms/README.md`
  documents importing, verifying, and activating local profiles.
- `tests/manifest.json` catalogs every runnable test, its suites, dependencies,
  fixtures, duration, and required outputs; `tests/run.py` records timestamped
  per-run metadata, logs, screenshots, and artifact hashes.
- `firmware/fast-start-patch.md` documents the optional, user-selectable ROM
  workaround that skips the missed startup checkpoint while preserving native
  result generation and validation.

Raw debugger `.tr` streams, diagnostic `.log` files, and framebuffer `.png`
captures are generated evidence and remain local rather than entering Git.
Tracked summaries, disassemblies, and Lua reproduction scripts preserve the
claims and make the bounded experiments repeatable.
