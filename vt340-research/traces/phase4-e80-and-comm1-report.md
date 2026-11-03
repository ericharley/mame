# Phase 4 E80 and Comm-1 POST boundary

## E80 result

CPU1 POST result bit 0 is the `NVR Error - 1` condition. The two routines
which control it are `3c27` and `3d5a`.

The February 1987 terminal-control schematic shows E80 on CPU1's external
address/data bus. E10 latches active-low `NVRCS` from the P1 NVR control
signals, while external read and write provide E80's output- and write-enable
strobes. Firmware routine `4156` clocks E10 immediately before each `MOVX`.
During those accesses P1.3 (`NVRDS L`) is low. E80 therefore owns the bus in
the observed `f000-f1ff` aperture; the previous driver incorrectly returned
shared RAM (and, at overlapping addresses, serial-device registers).

The recovered 512-byte `23-001N2` image independently satisfies both native
firmware checks:

| Firmware check | E80 bytes | Seeded 8-bit sum |
| --- | --- | ---: |
| `3c27` first block | `05a-06d` | `00` |
| `3c27` second block | `000-059` | `00` |
| `3d5a` configuration block | `100-1ff`, then `0e1-0ff` | `00` |

After decoding E80 ahead of overlapping devices while NVR select is active,
both `3c27` invocations return zero. `3d5a` returns zero, CPU1 deliberately
runs its second verification/copy pass, and POST result changes from `63` to
`62`. The original firmware no longer renders `VT340 NVR Error - 1`.

This is a hardware-derived correction. It does not force the result byte or
inject display commands.

The later write path is now implemented with MAME's X2804 device. Firmware
routine `3da9` performs the native compare-before-write operation and its
programming delay; changed bytes are saved by the standard MAME NVRAM
interface. A two-run regression changes Global On-Line/Local, invokes Save
Current Settings, and confirms the saved value is restored on a cold boot.
See `tests/nvram-persistence.sh`.

## Next observed boundary: Comm 1

This boundary has since been resolved. See
`phase4-scn2681-loopback-report.md` for the root cause, device correction,
and corrected full-channel traces.

Result bit 1 is set at CPU1 `4378` after the channel-A SCN2681 diagnostic.
The firmware programs local loopback, transmits test byte `a6`, and reads the
channel-A status register at `f041`. The first failing iteration observes
status `2d`; instruction `440d` masks it with `70`, producing `20`, and branch
`440f -> 43d8` marks the test failed. Bit `20` is the SCN2681 parity-error
status. Channel B follows the same path and sets result bit 5.

The trace therefore moves the next investigation from generic serial timing
to one exact question: why MAME's SCN2681 local loopback reports a parity error
for a frame generated and received by the same channel. No DUART state or
timing was changed in this round.

Evidence:

- `phase4-cpu1-bit0-diagnostic.lua`
- `phase4-cpu1-comm1-diagnostic.lua`
- `tests/phase4-e80-post.sh`
- `/tmp/vt340-post-timeout-125.png` from the controlled run
