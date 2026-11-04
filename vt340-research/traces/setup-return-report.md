# VT340 Set-Up return graphics trace

## Symptom

After leaving native Set-Up, the terminal session is replaced by broad vertical
color fields and repeated horizontal detail. In an interactive PTY session the
periodic redraw is perceived as extensive blinking. The same result is
reproducible with no host attached, so the macOS PTY transport is not causal.

`setup-return-trace.lua` drives only LK201 keys, records native DC323 commands,
and captures the visible bitmap before and after Set-Up exit.

## Confirmed DC323 scaling defect

The session rebuild uses 24 commands of the following form:

| Field | Value |
| --- | --- |
| Command | `0ed4` |
| Source rows | `1506` through `1529` |
| Destination rows | `0`, `20`, ..., `460` |
| Destination extent | `800 x 20` |
| Fast scale | `1fff` (unity) |
| Slow scale | `0199` (approximately 1:20 up-scaling) |

The Dragon specification defines the scale increment as the 13-bit magnitude
plus one, accumulated with a carry at `0x2000`. Thus `(0x0199 + 1) * 20`
crosses the carry threshold once: one source row is replicated across one
20-scanline terminal character row.

The extracted DC323 previously ignored registers `2a` and `2b` and read 20
successive source rows for every command. That explains the dense horizontal
mixing in the original failure. Normal-mode axis-aligned raster operations now
apply the documented independent fast and slow scale accumulators, including
source direction and up/down scaling. A firmware-free 1:20 regression covers
the exact Set-Up restore form.

## Bitmap-to-processor plane-selection defect

Scaling exposed a second independent defect in the Set-Up save/restore path.
CPU2 enters Set-Up by issuing X-mode processor-to-bitmap command `07e1` to
off-screen rectangle `(808,381)`, extent `192x264`, and streams the terminal's
character/attribute model through register 7. It then clears the RAM model.
On exit, routine `ce68` issues bitmap-to-processor command `0bc4`; `ce78-ce8b`
reads register 7 and reconstructs the model before the 24 scaled `0ed4`
commands restore the visible rows.

The native Viper programming identifies the data plane unambiguously:

| Transfer | Plane 0 | Plane 1 | Plane 2 | Plane 3 |
| --- | ---: | ---: | ---: | ---: |
| `07e1` logic function | `cc` | `cc` | `ca` | `cc` |
| `0bc4` source CSR 4 | `24` | `24` | `34` | `24` |

Function `ca` copies processor source data while `cc` preserves the old
destination. CSR bit 4 is the documented I/D-bus output enable. The firmware
therefore stores the model in plane 2 and selects plane 2 to drive the I/D bus
on restore.

The extracted DC323 device ignored the active CSR and always packed BTP bytes
from plane 0. Plane 0 correctly retained old off-screen data, including the
repeating `00/ff` pattern. CPU2 consequently reconstructed blank character
codes with mostly `ff` attributes and faithfully rendered the broad fields.
The earlier hypothesis that `bcf3/c1bf` rejected every twelfth cell was false:
the actual rebuild path runs through `c8ea-dec2`, and those routines merely
consumed the already-corrupt model.

The corrected BTP path retains the command-selected CSR, finds the selected
Viper whose CSR has I/D output enabled, and packs bitmap bytes from that plane.
It introduces no firmware address, terminal-specific condition, timing delay,
or forced status/data value.

After correction, CPU2 reads `00` rather than `ff` for the traced attribute at
`800d`. The visible framebuffer hash after leaving Set-Up is exactly the
pre-Set-Up hash (`2185572B`) and remains stable through the end of the run.

## Regression results

After both DC323 corrections:

- DC323 firmware-free device regression passes.
- focused BTP CSR/Viper-plane routing passes.
- VT340 POST passes.
- native Set-Up and Color Map selection pass.
- native Set-Up return restores the exact pre-Set-Up framebuffer.
- graphics raster-command regression passes.

The broader native SIXEL PTY run receives every input byte without mismatch,
but its existing color-output assertion still fails: the capture contains only
indices 0 and 14 rather than all 16 indices. That is a separate remaining
color-map/raster-path issue; bitmap-to-processor reads are not used to draw
those SIXEL pixels.
