# DC323 PC-qualified POST shim cleanup

## Scope

This round removed the two remaining DC323 firmware-address dependencies from
`vt340.cpp`:

- register-7 diagnostic readback at CPU2 `1bd1`;
- status-ready substitutions at `2900`, `bba0`, `bbaa`, and `bbb4`.

The bitmap AA/55/clear memory test and board reset sequencing remain separate
board behavior. No CPU PC is now consulted for a DC323 register read.

## Firmware sequence

`dc323-post-shim-audit.lua` records the native operations and the preceding
register writes. The four polling routines have stable hardware meanings:

| Firmware PC | Required status | Device event |
|---:|---|---|
| `2900` | Address Output Complete, bit 4 | idle/cancelled or completed address engine |
| `bba0` | Rasterop Initialization Complete, bit 2 | raster command accepted |
| `bbaa` | Address Output Complete, bit 4 | raster/address operation complete |
| `bbb4` | I/D Data Receive Ready, bit 5 | bitmap-to-processor FIFO has data |

The `1bc0-1bd1` routine issues diagnostic bitmap-to-processor command `0bc0`,
waits for bit 5, reads register 7 once, and returns the byte to the caller.
Earlier I/D values select either retained diagnostic data or the raster-address
pattern. Address bit 3 selects `aa` versus `55`. Firmware writes command zero
after the final diagnostic group and then waits for Address Output Complete.

## Root cause

Three device behaviors were missing:

1. Releasing the DC323 into operational mode did not initialize the idle
   raster-initialized, raster-complete, and address-complete outputs.
2. Diagnostic `0bc0` reads were supplied by the board driver, bypassing the
   device FIFO read and its completion transition.
3. Command `0000` did not abort the remaining diagnostic transfer and return
   the command/address engines to their completed idle state.

The board adapter hid all three by returning `55/aa/ff` at `1bd1` and ORing
status mask `3c` only at the four polling PCs.

## Device correction

The standalone DC323 now:

- asserts `STATUS_RASTEROP_MASK` when it becomes operational;
- retains equal-byte I/D diagnostic data, recognizes selectors `00cf` and
  `00c6`, and supplies the `0bc0` diagnostic source through `id_data_r()`;
- advances the normal FIFO/address state on those reads;
- treats command zero as transfer abort/idle, clearing FIFO-ready and
  asserting the three idle completion outputs.

Normal command-32 `0bc4` PBT remains on the bitmap/E49 data path and is not
classified as a diagnostic transfer.

## Verification

The firmware-free DC323 test covers idle ready state, both raster diagnostic
patterns, retained `ff`, FIFO completion, and command-zero abort. The complete
firmware audit recorded:

```text
id_data=3378 initialized=800 address_low=3634 address_bank=458 id_ready=4402
failures=0/0/0/0
```

Additional passing checks:

- targeted build and smoke test;
- Phase 3 low-ROM checkpoint;
- optional fast-start result validation;
- command-32 PBT: 1,024 FIFO reads and 1,024 stored bytes;
- unchanged startup-string bytes `5654330030204F4B4572726F72202D19`.

After this cleanup the remaining PC-qualified hardware behavior in
`vt340.cpp` is limited to the CPU1 board-read strobe (`3940/3941`) and the
initial DAT9 retention (`1703/3925`).
