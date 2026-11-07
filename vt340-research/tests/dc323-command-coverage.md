# DC323 command implementation and test coverage

This file is generated from `dc323-command-catalog.json`, test claims in
`manifest.json`, and per-case claims in `vt340test-cases.json`. Run
`tests/dc323-command-coverage.sh` after changing DC323 behavior or tests.

Coverage levels: **direct** is a targeted firmware-free assertion;
**integration** couples native command activity to an asserted visible or
read-back result; **negative** verifies a no-draw/unsupported boundary; and
**observed** records trace occurrence without claiming semantic coverage.

| Command family | Encoding/context | State | Required | Coverage | Remaining boundary |
| --- | --- | --- | --- | --- | --- |
| `command.abort` — Command-zero abort | command = 0000 | implemented | direct | `dc323-device` (direct) | Exact asynchronous abort/FIFO timing is unresolved. |
| `viper.register-load` — Selected Viper register load | command = 0180-019F | implemented | direct | `dc323-device` (direct) | No known functional gap in the retained per-plane model. |
| `raster.normal-constant` — Normal raster with constant source | op=2 D=1 S1=0 S2=0, X-control mode 00 | implemented | direct | `dc323-device` (direct); `graphics-raster-commands` (integration); `vt340test-corpus/regis-grid` (integration); `vt340test-corpus/regis-raf` (integration) | Exact traversal direction controls remain. |
| `raster.normal-bitmap` — Normal raster with bitmap source 1 | op=2 D=1 S1=1 S2=0, X-control mode 00, bitmap source | implemented | direct | `dc323-device` (direct); `setup-return` (integration); `vt340test-corpus/regis-grid` (integration); `vt340test-corpus/regis-raf` (integration); `vt340test-corpus/sixel-editing` (integration); `vt340test-corpus/sixel-line-attributes` (integration); `vttest-double-size-blink` (integration); `vttest-screen-features` (integration) | Overlap traversal direction remains. |
| `raster.normal-e49` — Normal raster with E49 character-ROM source 1 | op=2 D=1 S1=1 S2=0, X-control mode 00, source Y bit 12 | implemented | integration | `graphics-raster-commands` (integration); `vttest-double-size-blink` (integration) | A firmware-free character-ROM pixel test would strengthen coverage. |
| `raster.normal-hole-fill` — Normal-mode hole filling | op=2 D=1 S1=0 S2=0, X-control mode 00, HF=1 | partial | direct | `dc323-device` (direct) | Source-coupled holes, complement corrections, and exact silicon edge cases are unresolved. |
| `raster.normal-indexed` — Normal raster with nonzero indexes | op=2, X-control index enabled, any old/new index nonzero | partial | direct | `dc323-device` (direct) | Old/new selection and upward bitmap movement follow the live DC7051 raster line; exact silicon arbitration remains unresolved. |
| `raster.error-offsets` — Programmable Bresenham error offsets | register 2F offsets destination slow/edge A; register 30 offsets destination fast/edge B | implemented | direct | `dc323-device` (direct) | Extreme adjustment overflow behavior has not been compared with physical silicon. |
| `raster.destination-disabled` — Raster operation with destination disabled | op=2 D=0 | no-op | direct | `dc323-device` (direct) | Observed firmware forms appear diagnostic; no visible operation is established. |
| `raster.reserved-mode` — Reserved X-control mode 01 | op=2 D=1, X-control mode 01 | no-op | direct | `dc323-device` (direct) | No drawing behavior is inferred without hardware evidence. |
| `raster.linear-source1` — Linear-pattern raster with source 1 | op=2 D=1 S1=1 S2=0, X-control mode 10 | implemented | direct | `dc323-device` (direct); `sixel-bill-pty` (integration); `sixel-color-indices` (integration); `vt340test-corpus/regis-grid` (integration); `vt340test-corpus/sixel-editing` (integration); `vt340test-corpus/sixel-line-attributes` (integration); `vt340test-corpus/sixel-overlap` (integration); `vt340test-corpus/sixel-raster-size` (integration); `vt340test-corpus/sixel-repeat` (integration); `vt340test-corpus/sixel-scrolling` (integration) | No known functional gap; exact sampling artifacts remain subject to physical-silicon comparison. |
| `raster.linear-constant` — Source-free linear-pattern encoding | op=2 D=1 S1=0 S2=0, X-control mode 10 | no-op | direct | `dc323-device` (direct) | Dragon defines linear-pattern mode around source 1; the no-source form is an illegal command combination with undefined hardware results. |
| `raster.fill-two-edge` — X/Y two-edge fill | op=2 D=1 S1=0 S2=0, X-control mode 11, baseline=0 | partial | direct | `dc323-device` (direct) | Unequal and crossing edges execute; complement-mode vertex-doubling corrections remain. |
| `raster.fill-baseline` — X/Y baseline fill | op=2 D=1 S1=0 S2=0, X-control mode 11, baseline=1 | partial | direct | `dc323-device` (direct) | Hardware comparison and complement interactions remain. |
| `raster.fill-chained` — Chained polygon fill edges | successive op=2 fill commands without origin reload | partial | direct | `dc323-device` (direct) | Independent edge expiration and crossing continuation are implemented; complement-mode vertex-doubling corrections remain. |
| `raster.source2` — Raster source 2 | op=2 S2=1 | partial | direct | `dc323-device` (direct) | Source-2-only addressing/fills and dual-source CSR routing are implemented; exact Viper word-pipeline, delay-register, and multiple-driver behavior remains. |
| `transfer.bitmap-to-processor-x` — X-mode bitmap-to-processor transfer | op=3 D=0 S1=1 | partial | direct | `dc323-device` (direct); `phase4-pbt-transfer` (integration) | Six-entry FIFO flow and staged command status are modeled; exact per-memory-cycle transfer cadence remains provisional. |
| `transfer.processor-to-bitmap-x` — X-mode processor-to-bitmap transfer | op=3 D=1 S1=0 | partial | direct | `dc323-device` (direct); `sixel-bill-pty` (integration); `sixel-color-indices` (integration); `vt340test-corpus/sixel-editing` (integration); `vt340test-corpus/sixel-line-attributes` (integration); `vt340test-corpus/sixel-overlap` (integration); `vt340test-corpus/sixel-raster-size` (integration); `vt340test-corpus/sixel-repeat` (integration); `vt340test-corpus/sixel-scrolling` (integration) | Six-entry FIFO back-pressure and asynchronous service are modeled; exact per-memory-cycle transfer cadence remains provisional. |
| `transfer.z-mode` — Z-mode processor/bitmap transfer | op=3 with Z-mode selection | partial | direct | `dc323-device` (direct) | One-bit Viper plane addressing, Z blocks, and foreground/background PTB paths are implemented; low-resolution subplanes and the board-inaccessible upper I/D byte remain. |
| `transfer.other` — Other operation-3 source/destination forms | op=3 excluding established X- and Z-mode PBT/PTB forms | unsupported | none | — | No defined behavior has been established. |
| `scroll.frame-service` — Raster-synchronous vertical scroll/erase | register 14 load, started by frame event | partial | direct | `dc323-device` (direct); `graphics-raster-commands` (integration); `vttest-screen-features` (integration) | Up-scroll is scanline-progressive; pause/scroll status phase and the two-event pause queue are covered. Multiple pending-command queueing and exact silicon arbitration remain provisional. |

## Per-test scope

| Test or case | Level | Command family | What the test actually asserts |
| --- | --- | --- | --- |
| `dc323-device` | direct | `command.abort` | Aborts an active diagnostic transfer and asserts completed idle status. |
| `dc323-device` | direct | `raster.destination-disabled` | Verifies an operation-2 command with destination disabled leaves the target unchanged. |
| `dc323-device` | direct | `raster.error-offsets` | Checks signed ERR1/ERR2 shifts on destination fast and slow vectors and independent fill edges A and B. |
| `dc323-device` | direct | `raster.fill-baseline` | Checks sloped X and Y edges against fixed baselines. |
| `dc323-device` | direct | `raster.fill-chained` | Checks X/Y diamonds, explicit restart, unequal edge expiration with one-sided reload, and scan reversal after crossing. |
| `dc323-device` | direct | `raster.fill-two-edge` | Checks X-fill and Y-fill interiors, exteriors, and excluded endpoints. |
| `dc323-device` | direct | `raster.linear-constant` | Verifies the undocumented source-free linear-pattern encoding does not invent visible output. |
| `dc323-device` | direct | `raster.linear-source1` | Checks rotation, fast up/down scaling, retained slow position and fractional phase, pen-up advancement, origin reset, and raster-phase indexing. |
| `dc323-device` | direct | `raster.normal-bitmap` | Checks bitmap copies, overlap behavior, and 1:20 Set-Up restoration scaling. |
| `dc323-device` | direct | `raster.normal-constant` | Checks constant fills, masks, clipping, signed vectors, scaling, and Bresenham pixels. |
| `dc323-device` | direct | `raster.normal-hole-fill` | Compares rotated broad vectors with hole filling off and on at exact interior pixels. |
| `dc323-device` | direct | `raster.normal-indexed` | Checks source/destination indexing, signed offsets, frame rollover, and old/new selection above and below the live raster boundary. |
| `dc323-device` | direct | `raster.reserved-mode` | Verifies X-control mode 01 produces no drawing. |
| `dc323-device` | direct | `raster.source2` | Checks source-2 copies, indexing independence, tiling, patterned fills, dual-source internal routing through both CSR banks, cross-plane I/D-bus broadcast, and linear-pattern routing. |
| `dc323-device` | direct | `scroll.frame-service` | Checks deferred up/down scroll, scanline-progressive upward movement, erase, edge masks, offsets, pending-command replacement, exact pause-coordinate matching, and the two-event pause queue. |
| `dc323-device` | direct | `transfer.bitmap-to-processor-x` | Checks selected-plane packing, six-entry FIFO prefetch/drain, I/D readback, and completion status. |
| `dc323-device` | direct | `transfer.processor-to-bitmap-x` | Checks aligned/unaligned writes, masks, CSR routing, six-word back-pressure, cancel, and asynchronous status. |
| `dc323-device` | direct | `transfer.z-mode` | Checks plane-addressed PTB unpacking and BTP packing for two adjacent pixels in a Z block. |
| `dc323-device` | direct | `viper.register-load` | Loads independent per-plane Viper registers and verifies retained values and color indices. |
| `graphics-raster-commands` | integration | `raster.normal-constant` | Counts the six native late clear rasters and verifies their resulting screen regions. |
| `graphics-raster-commands` | integration | `raster.normal-e49` | Verifies firmware-drawn Wait/status/VT340 OK regions through native character-ROM rasters. |
| `graphics-raster-commands` | integration | `scroll.frame-service` | Requires the native frame-boundary 800x480 erase while preserving the status line. |
| `phase4-pbt-transfer` | integration | `transfer.bitmap-to-processor-x` | Requires native command 0BC4 to return the exact 1,024-byte E49 startup block. |
| `setup-return` | integration | `raster.normal-bitmap` | Requires the restored framebuffer to match before Set-Up after native 1:20 bitmap scaling. |
| `sixel-bill-pty` | integration | `raster.linear-source1` | Requires the staged full-color Bill image to transfer into the visible framebuffer. |
| `sixel-bill-pty` | integration | `transfer.processor-to-bitmap-x` | Requires the full host SIXEL stream to stage into bitmap memory without receive mismatches. |
| `sixel-color-indices` | integration | `raster.linear-source1` | Requires staged SIXEL patterns to reach the visible bitmap through all 15 image-used indices. |
| `sixel-color-indices` | integration | `transfer.processor-to-bitmap-x` | Requires native SIXEL staging to produce the 15 framebuffer indices painted by the fixture prefix; exhaustive 0-15 routing is direct-tested. |
| `vt340test-corpus/regis-grid` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers its patterned grid lines. |
| `vt340test-corpus/regis-grid` | integration | `raster.normal-bitmap` | The exact grid framebuffer covers native source-1 text and composition. |
| `vt340test-corpus/regis-grid` | integration | `raster.normal-constant` | The exact grid framebuffer covers native constant-source vectors. |
| `vt340test-corpus/regis-raf` | integration | `raster.normal-bitmap` | The exact RAF framebuffer covers native source-1 composition commands. |
| `vt340test-corpus/regis-raf` | integration | `raster.normal-constant` | The exact RAF framebuffer depends on native constant-source circle/fill spans. |
| `vt340test-corpus/sixel-editing` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers staged image placement. |
| `vt340test-corpus/sixel-editing` | integration | `raster.normal-bitmap` | The final hash covers native bitmap movement during insert/delete operations. |
| `vt340test-corpus/sixel-editing` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover initial SIXEL staging. |
| `vt340test-corpus/sixel-line-attributes` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers attributed-line placement. |
| `vt340test-corpus/sixel-line-attributes` | integration | `raster.normal-bitmap` | The final hash covers backing-buffer restoration and line erasure copies. |
| `vt340test-corpus/sixel-line-attributes` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover SIXEL staging on attributed lines. |
| `vt340test-corpus/sixel-overlap` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers transparent pattern composition. |
| `vt340test-corpus/sixel-overlap` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover layered SIXEL staging. |
| `vt340test-corpus/sixel-raster-size` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers raster-sized placement. |
| `vt340test-corpus/sixel-raster-size` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover raster-sized SIXEL staging. |
| `vt340test-corpus/sixel-repeat` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the hash covers staged pattern placement. |
| `vt340test-corpus/sixel-repeat` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover native SIXEL column staging. |
| `vt340test-corpus/sixel-scrolling` | integration | `raster.linear-source1` | The trace contains X-control mode 00C2 and the final hash covers visible placement. |
| `vt340test-corpus/sixel-scrolling` | integration | `transfer.processor-to-bitmap-x` | Exact UART and framebuffer checks cover SIXEL staging across scrolling operations. |
| `vttest-double-size-blink` | integration | `raster.normal-bitmap` | Checks the periodic 1:20 bitmap-sourced blink refresh after a 132-to-80-column transition. |
| `vttest-double-size-blink` | integration | `raster.normal-e49` | Checks 2x-scaled top/bottom DECDHL glyph construction from E49 character ROM data. |
| `vttest-screen-features` | integration | `raster.normal-bitmap` | Checks text reconstruction, rendition attributes, and DECSC/DECRC output after the scroll sequence. |
| `vttest-screen-features` | integration | `scroll.frame-service` | Exercises small and full-height smooth and jump scrolling in both directions before checking later display integrity. |

## Change policy

When a family moves from `unsupported` to `partial` or `implemented`, give
it the required direct/integration claim in the same change. A test should
claim only behavior it asserts; merely seeing a command in a boot trace is
`observed`, not functional coverage. Split a family when new behavior has a
distinct mode or state boundary that can regress independently.
