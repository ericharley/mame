# DEC VT340 ROM-level emulator research

This directory records the evidence behind the first-stage MAME driver in
`src/mame/dec/vt340.cpp`.  Assertions are classified as confirmed, inferred,
or unresolved.  The original ROM binaries are intentionally kept outside
tracked source under `roms/vt340/`.

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

Start here:

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
- `firmware/fast-start-patch.md` documents the optional, user-selectable ROM
  workaround that skips the missed startup checkpoint while preserving native
  result generation and validation.

Raw debugger `.tr` streams, diagnostic `.log` files, and framebuffer `.png`
captures are generated evidence and remain local rather than entering Git.
Tracked summaries, disassemblies, and Lua reproduction scripts preserve the
claims and make the bounded experiments repeatable.
