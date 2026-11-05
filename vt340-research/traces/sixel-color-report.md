# VT340 native color SIXEL report

## Result

The native firmware now renders complete color SIXEL without a framebuffer
injection, hardcoded palette, firmware patch, or PC-dependent trigger. A
macOS pseudo-terminal run selected **Color Map: color** through emulated LK201
keys, received SIXEL through Comm 1, programmed all 16 E51/E52 output-map
entries, and rendered the complete orange/yellow Bill image.

## Hardware corrections

- PAL E16 maps E51 at `f080-f09f` and E52 at `f0a0-f0bf`; BA4 is an alias.
  These ranges were previously assigned incorrectly to DC7051 registers.
- E51's low nibble is red. E52's high nibble is green and its low nibble is
  blue, matching the schematic `DA3-DA0` and `DB3-DB0` wiring.
- Output-map writes become visible as soon as both halves of an entry have
  been programmed. No CPU-interrupt or first-glyph policy gate exists on the
  board.
- Schematic sheet 8 wires the CNTLWR latch's `BAD3-BAD0` inputs to
  `V0CS-V3CS`; `BAD5` drives the separate `OPADDS` output. The former
  contiguous `BAD5-BAD2` decode collapsed firmware colors into indices
  `3,7,11,15`.
- The BP0 scanout wiring gives the Viper serial outputs the reverse bit
  significance at the E51/E52 address latch from the DC323 device's internal
  plane numbering. The former direct lookup made Color Set-Up entries `1-5`,
  `7-8`, and `10-14` alter a different preview strip. Only the bit-reversal
  fixed points `0`, `6`, `9`, and `15` appeared to work. Scanout now performs
  that physical four-bit translation before looking up the programmed RGB.
- The full VT340 model identity exposes the firmware's Color Map and Color
  Set-Up controls. The exact off-sheet source that resolves CPU1 P1.7 low for
  this identity is still not identified and remains an explicit wiring
  inference.

## Firmware decision

CPU1 loads E80 EEPROM offset `5a` into saved configuration `7b00` and working
state `4c00`. The recovered EEPROM has a valid checksum and value `28`; this
is a native saved **monochrome** choice, not corrupt NVRAM. CPU2's output-map
loader selects its grayscale tables when `4c00` bit 4 is clear and color
tables when it is set.

`color-setup-trace.lua` enters Global Set-Up with LK201 keypad Enter, moves to
the eighth row with seven LK201 Down keys, and presses LK201 Right. Firmware
changes working state from `28` to `38`. The trace never writes configuration,
palette, or bitmap memory. Choosing **Save Current Settings** in the Set-Up
Directory persists the same change through the existing X2804 NVRAM model.

## Observed native palette

The Bill stream produced 256 writes to each output-map aperture and these
final entries:

| Index | E51 | E52 | Decoded RGB |
| ---: | ---: | ---: | ---: |
| 1 | `ce` | `ca` | `eeccaa` |
| 3 | `ce` | `b3` | `eebb33` |
| 11 | `ae` | `81` | `ee8811` |
| 14 | `24` | `21` | `442211` |
| 15 | `01` | `00` | `110000` |

This palette and the visible orange/yellow pixels came from original firmware
commands over the normal DC323 four-plane path. The successful full run read
all 93,198 bytes with zero mismatches, processed 901 XOFF and 901 XON bytes,
and originally exposed the four-index collapse caused by the incorrect Viper
select decode. With the schematic-correct latch mapping, the first 4,096-byte
window leaves nonzero image pixels in 15 framebuffer indices. An earlier
capture appeared to cover index 8 as well, but its exact 200-pixel contribution
was the independently blinking 10x20 text cursor, not SIXEL image data. The
firmware-free `dc323-device` regression remains the exhaustive check of all 16
index values. A complete post-fix run passes the PTY acceptance test and
renders Bill with the full set of shades used by the image (several palette
entries intentionally quantize to the same 12-bit RGB value).

`sixel-color-indices.sh` fixes the input at the first 4,096 bytes and requires
at least 15 framebuffer-index counts to be nonzero. This is the focused native-
firmware regression for the Viper-select wiring without treating cursor blink
phase as image coverage; the complete Bill run remains the sustained-stream
integration workload.

## Remaining issue

Earlier long runs sometimes left DCS mode and displayed trailing SIXEL bytes
as text. The byte-comparison instrumentation and a raw PTY run then completed
with zero mismatches and balanced flow control, producing the full image.
`sixel-bill-pty.sh` preserves that exact path as the visual acceptance test,
with `sixel-bill.sh` as its conventional entry point. The older bitbanger
transport was retired from the named regression because its shared
bidirectional file position is less representative of the user's macOS
PTY/getty path.

After adding byte comparison, the acceptance path passed two consecutive cold
boots. One earlier packaged run still left DCS mode, so sustained-stream
repeatability is improved but not yet declared perfect. If the failure recurs,
the test preserves its run directory and the new first-mismatch event
distinguishes serial corruption from a parser-state failure immediately.

## Gnuplot animation background mode

Gnuplot 6.0.6 `sixelgd` emits every anchored frame with `DCS 9;1q`. Parameter
two equal to one requests transparent background handling. A native trace
shows CPU2 consequently programming the four Viper logic functions to
`ce,ce,cc,cc` for the full-width background bands: selected planes are ORed
and the others are preserved. This faithfully explains why old wave pixels
remain under later frames; no DC323 erase command is dropped.

A controlled two-frame experiment changed only the DCS parameter to
`DCS 9;0q`. Native firmware then took its opaque-background clear path. The
captured result displayed **Frame 1** without any pixels from **Frame 0**.
The same experiment established that formatting LF bytes in gnuplot's output
become CR/LF on a macOS tty configured with `ONLCR`, so the compatibility
wrapper removes those optional newlines as well.

`../tools/vt340-gnuplot` applies both stream-level compatibility changes. It
does not modify the emulator, firmware, palette, or framebuffer.
