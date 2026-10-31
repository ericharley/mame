# Milestones

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
- [x] Retain the aliased DC7051 F080-F0BF timing-register apertures.
- [x] Pass the DC7051 vertical-period check at the ROM's accepted `0cfb-0cfd` count.
- [x] Resolve the initial multiplexed DAT9 status/report phases and CPU1's
  `7ff2=10` / CPU2 `7ff2=80` POST report exchange.
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
- [ ] Add destination-only/source-2 operations, fill modes, and scrolling.
- [x] Decode E51/E52 palette apertures and separate destructive POST writes from operational entries.
- [ ] Observe and display the first post-POST firmware-programmed 12-bit RGB entry.
- [x] Decode the `7e00` command ring and repair corrupted E4 byte `12ff`
  (`92ff` in CPU space), restoring the native packet-length store and
  indirect handler dispatch without a synthetic stack frame.
- [x] Replace CPU1's provisional serial-register bytes with SCN2681 and
  SCN2641 devices and connect their documented INT0/INT1 lines.
- [x] Keep CPU1 stable through its normal serial-service burst by providing
  the upper indirect RAM the ROM demonstrably uses through address `8c`.
- [x] Trace the stable loop's `0ec0` glyph stream and confirm that its final
  blank-glyph/logic-`81` sweep intentionally clears all four visible planes.
- [ ] Reach the documented successful power-up display (`VT340 OK`, firmware
  revision, and copyright message) rather than treating a black idle screen as
  the expected POST result.
- [x] Display the first persistent post-POST firmware-written pixel; the full
  startup message is not yet present.
- [x] Prove the missing `VT340 OK` banner is not an ignored operational
  rasterop, PBT transfer, or nonzero DC323 scanout offset/index/scroll state.
- [x] Hold unconnected SCN2681 and SCN2641 receive inputs at the serial marking
  level instead of allowing a zero-initialized break condition.
- [ ] Remove the monochrome fallback after firmware initialization of all displayed entries is understood.
