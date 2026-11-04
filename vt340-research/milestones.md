# Milestones

Reviewed: 2026-11-04.

The native target runs the original firmware through successful POST and
interactive text, ReGIS, and color SIXEL sessions. A packaged WebAssembly
preview also runs in Chromium with a WebSocket-to-PTY bridge and persistent
browser settings. The authentic fast startup handshake remains unresolved;
normal cold boot still reaches success through the firmware's roughly
120-second timeout. An optional fast-start ROM patch is a separate convenience,
not completion of that hardware milestone.

Checked items below record achieved checkpoints, not complete hardware
conformance. Validation references describe recorded evidence; this document
review did not rerun the native regression suites.

## Firmware, hardware, and native display

- [x] Retrieve E1-E5 and E49 from the VT340 Internals archive.
- [x] Record reproducible size, CRC32, SHA-1, and SHA-256 values.
- [x] Identify E57 and E24 as 8031 processors clocked from 12 MHz.
- [x] Establish lower/reset ROM mapping and CPU ownership from J5 wiring.
- [x] Add a two-CPU MAME driver skeleton using genuine ROM bytes.
- [x] Build the targeted executable.
- [x] Record a deterministic one-second boot/XDATA checkpoint.
- [x] Implement the first blocking external-data dependency: shared RAM.
- [x] Resolve CPU2's indirect accesses to internal addresses `80-ff` against
  the documented 8031 part and the board's actual processor population.
- [x] Decode the first real external register overlay: DC323 Adder register 3 status.
- [x] Model CPU2 P1.1 (`P2 DAT9/STATUS H`) driving CPU1's external T1 input.
- [x] Classify and retain CPU2's first 16-bit DC323 Adder register writes.
- [x] Localize CPU1's first bad path to the B.0-dependent branch at `09e4`.
- [x] Resolve CPU1's formatter path by returning `ff` from reserved SFR `c2`.
- [x] Reach CPU1's first interprocessor completion wait at shared RAM `7ff1`.
- [x] Reconstruct CPU1 E1/E2 missing tail bytes from the ROM's own rotate/XOR checksums.
- [x] Synchronize the bidirectional CPU2 P1.1 / CPU1 T1 power-on handshakes.
- [x] Pass the DC323 bitmap AA, zero/readback, complement, and final clear sweeps.
- [x] Correct F080/F0A0 ownership from presumed DC7051 registers to the
  schematic E51/E52 output maps; DC7051's CPU-visible programming remains
  unidentified.
- [x] Pass the DC7051 vertical-period check at the ROM's accepted `0cfb-0cfd` count.
- [x] Identify the initial multiplexed DAT9 status/report phases and CPU1's
  `7ff2=10` / CPU2 `7ff2=80` POST report exchange.
- [ ] Correct the startup ordering so CPU1 installs pending `7ff2=10` before
  CPU2 publishes checkpoint `7ff2=00` and final result `7ff2=80`.
- [x] Model DC323 register 3's separate control-write/status-read behavior so
  each level-triggered frame interrupt is acknowledged exactly once.
- [x] Add exact 800x500 active raster timing and a MAME screen device.
- [x] Identify DC323 registers 08/09 and 20-3f from DEC's chipset specification.
- [x] Decode the first observed text rasterops as the string `Wait`; subsequent
  synchronized POST work classifies this as the delayed-status/failure path,
  not the normal idle screen.
- [x] Recover E49's schematic address-pin permutation and XCON mode.
- [x] Resolve the DC323 major-cycle phase and DC322 byte alignment for E49.
- [x] Render the first genuine firmware text (`Wait`) from E49 at its DC323 destination.
- [x] Retain Viper logic-function loads and render the proven text path into four independent bitmap planes.
- [x] Generalize normal source/destination rasterops across E49 and four-plane bitmap sources.
- [x] Implement frame-boundary erase and hardware text scrolling, including
  edge-mask handling for the leftmost column.
- [ ] Add source-2 operations and remaining fill/non-normal raster modes.
- [x] Decode E51/E52 palette apertures and separate destructive POST writes from operational entries.
- [x] Decode and display all post-POST firmware-programmed 12-bit RGB entries.
- [x] Decode the `7e00` command ring and repair corrupted E4 byte `12ff`
  (`92ff` in CPU space), restoring the native packet-length store and
  indirect handler dispatch without a synthetic stack frame.
- [x] Replace CPU1's provisional serial-register bytes with SCN2681 and
  SCN2641 devices and connect their documented INT0/INT1 lines.
- [x] Investigate CPU1's serial-service stack excursion through address `8c`
  using an upper-indirect-RAM compatibility experiment. The I8032 workaround
  was subsequently removed; the schematic-correct I8031 remains in use and
  the excursion remains an open hardware risk.
- [x] Trace the stable loop's `0ec0` glyph stream and confirm that its final
  blank-glyph/logic-`81` sweep intentionally clears all four visible planes.
- [x] Reach the documented successful power-up display (`VT340 OK`, firmware
  revision, and copyright message) rather than treating a black idle screen as
  the expected POST result.
- [x] Display persistent post-POST firmware output through the complete
  startup success panel.
- [x] Prove the missing `VT340 OK` banner is not an ignored operational
  rasterop, PBT transfer, or nonzero DC323 scanout offset/index/scroll state.
- [x] Hold unconnected SCN2681 and SCN2641 receive inputs at the serial marking
  level instead of allowing a zero-initialized break condition.
- [ ] Remove the monochrome fallback after firmware initialization of all displayed entries is understood.

## Interactive terminal and graphics

- [x] Exercise the ROM-driven LK201 keyboard and interactive PTY shell sessions.
- [x] Expose Comm 1 and Comm 2 through MAME RS-232 endpoints.
- [x] Support firmware Set-Up and persistent E80/X2804 NVRAM settings.
- [x] Exercise text scrolling, return from Set-Up, ReGIS, and color SIXEL.
- [x] Render the complete color Bill SIXEL fixture through the PTY acceptance
  path, with byte-level transport comparison.
- [x] Extract DC323 and DC7051 into standalone devices with focused regressions.
- [x] Provide an optional fast-start ROM patch with a separate regression.
- [x] Add native 2×/4× prescaling and smoothing launch options.
- [x] Catalog native tests with a common runner and retained evidence.

## Browser / WebAssembly preview

- [x] Build the targeted VT340 runtime with Emscripten 6.0.2 and SDL3.
- [x] Correct browser SDL3 renderer registration and newer-Chromium memory compatibility.
- [x] Package VT340/LK201 ROMs, a 512-byte EEPROM seed, and keyboard settings.
  Generated ROM-containing packages remain private and ignored by Git.
- [x] Add scale/smoothing controls and a raw binary WebSocket serial adapter.
- [x] Provide a loopback PTY bridge with session-token and same-origin checks.
- [x] Verify browser keyboard input and shell output with `echo ok`.
- [x] Verify all 256 byte values through the PTY bridge independently of the emulator.
- [x] Flush EEPROM/configuration on explicit stop and persist files in IndexedDB;
  verify storage survives reload. Closing a tab alone is not a save step.
- [x] Provide SSH launch mode using the bridge host's system SSH client.
- [ ] Validate SSH login against an actual remote destination.
- [ ] Validate SIXEL/ReGIS transport end to end in the browser.
- [ ] Expand browser compatibility and scale/performance coverage beyond the
  current Chromium checks.

The measured runtime is approximately 21 MiB; the ZIP with assets is about
4.9 MiB. SSH uses the companion bridge. This remains a local development
preview, not an internet-facing terminal service. See [browser instructions
and validation](browser/README.md).

## Remaining priorities and validation

- Resolve the authentic DAT9/`7ff2` startup race without forcing firmware
  decisions or treating the optional fast-start patch as a hardware fix.
- Complete unsupported raster modes, palette behavior, and the focused device
  correctness work in [the DC323 assessment](hardware/dc323-next-steps.md).
- Retain the existing open hardware risks documented in
  [sprint status](SPRINT_STATUS.md) and [project summary](PROJECT_SUMMARY.md).
- Validate remote SSH and browser graphics transport separately from native
  graphics acceptance. Successful terminal text does not prove graphics conformance.

Native test inventory and recorded evidence are described in
[the test guide](tests/README.md). From the MAME checkout root, run the default
suite with:

```sh
vt340-research/tests/run.py run
```

Browser checks and their dependencies are documented in
[browser validation](browser/README.md#validation).
