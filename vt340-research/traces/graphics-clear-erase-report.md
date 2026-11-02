# VT340 graphics clear/erase diagnostic

## Result

The stale visible `Wait` text was caused by missing DC323 frame-boundary scroll
erase behavior, not by a rasterop that directly overlaps the glyphs.

At 124.024578 seconds CPU2 PC `BB6F` writes Y scroll constant register 14 with
`2001`.  The active scroll bounds are X=`0000..0320` and Y=`0000..01E0`, the
Y offset is zero, and the Viper fill word is zero.  Bit 13 is the documented
erase-mode request: at the following vertical frame boundary the DC323/Vipers
replace the full 800x480 main-screen region with the fill color.  The previous
driver retained these registers but never performed that operation.

The driver now schedules register-14 writes for the next frame and implements
the documented erase over the exclusive scroll bounds.  Original firmware
therefore clears `Wait` before drawing `VT340 OK`; the 20-pixel status line is
correctly outside this particular erase region.

The trace also found one independently verified missing raster command class.

The DC323 specification says that every rasterop has a destination and may
have zero, one, or two memory sources.  With zero memory sources, the Viper
source register supplies the constant.  The driver previously required source
1 and silently rejected all zero-source forms.  Normal-mode zero-source
rasterops are now implemented without adding source-2, fill-mode, or
PC-specific behavior.

The complete cold-boot inventory contains 4,596 rasterop-form commands:

| Classification | Count | Driver behavior after correction |
| --- | ---: | --- |
| Normal mode, source 1, destination | 1,164 | Executed |
| Normal mode, zero memory sources, destination | 35 | Executed |
| Non-normal mode | 3,347 | Rejected; semantics not yet implemented |
| Destination disabled diagnostic forms | 50 | Rejected |
| Destination-enabled source 2 | 0 | Not observed |

The 35 newly supported commands are `06C0` x25, `06F0` x6, `06D1` x3, and
`06D4` x1.  The much larger apparent `06F0` population belongs to mode `7590`,
not normal mode, and remains rejected.

## Structured trace

`graphics-command-trace.lua` emits one JSON object per line with the prefix
`VT340_GFX_JSON`.  It records all 11,731 writes to DC323 register 8, including
I/D loads and PBT commands, and decodes:

- emulation time and CPU2 PC;
- raw command, function, source and destination enables;
- mode, XCON, origins, extents, masks, logic function, Viper source and fill;
- supported/rejected classification and reason;
- exact changed-pixel and changed-plane-bit counts for the late rasterops;
- command intersection and bitmap hashes for the four configured regions;
- palette writes and timestamped screen snapshots.

The four exact diagnostic regions are:

| Region | Bounds, inclusive | Firmware rectangle |
| --- | --- | --- |
| `WAIT` | `(0,0)-(39,19)` | Four 10x20 character cells |
| `STATUS` | `(0,480)-(799,499)` | Visible 25th line |
| `POST_OK` | `(300,200)-(499,259)` | Success-panel rectangle |
| `COPYRIGHT` | `(180,380)-(619,439)` | Two copyright text rows |

The visible nonblack pixels in the 130-second snapshot are contained within
`(1,4)-(38,14)`, `(304,209)-(495,250)`, `(182,384)-(618,398)`, and
`(261,424)-(548,438)`, respectively.  The larger configured bounds follow the
actual command rectangles rather than only the lit glyph pixels.

Reproduction:

```sh
./vt340 vt340 -rompath roms -video none -sound none -nothrottle \
  -seconds_to_run 300 -autoboot_delay 0 \
  -autoboot_script vt340-research/traces/graphics-command-trace.lua \
  > /tmp/vt340-graphics.log 2>&1
rg '^VT340_GFX_JSON ' /tmp/vt340-graphics.log | \
  sed 's/^VT340_GFX_JSON //' > /tmp/vt340-graphics.jsonl
```

Raw generated logs and screenshots remain untracked, consistent with the
repository's trace policy.

## Late clear candidates

Six zero-source clears occur after 115 seconds:

| Time (s) | CPU2 PC | Command | Destination | Extent | Logic | Changed pixels |
| ---: | --- | --- | --- | --- | --- | ---: |
| 120.091815 | `BB6F` | `06F0` | `(0,522)` | `800x20` | `C0` / zero | 0 |
| 120.094001 | `BB6F` | `06F0` | `(0,522)` | `800x20` | `C0` / zero | 0 |
| 120.301422 | `BB6F` | `06F0` | `(0,522)` | `800x20` | `C0` / zero | 0 |
| 120.305016 | `BB6F` | `06F0` | `(0,522)` | `800x20` | `C0` / zero | 0 |
| 123.963150 | `BB6F` | `06F0` | `(0,522)` | `800x20` | `C0` / zero | 0 |
| 124.024434 | `9B03` | `06D4` | `(0,1506)` | `800x24` | `C0` / zero | 0 |

All six execute after the correction, but both off-screen target bands are
already zero.  They do not intersect `WAIT`, `STATUS`, `POST_OK`, or
`COPYRIGHT`.  They are legitimate hardware operations, not the missing direct
erase of visible `Wait`.

## Region timeline

| Time (s) | `WAIT` hash | `STATUS` hash | `POST_OK` hash | `COPYRIGHT` hash |
| ---: | --- | --- | --- | --- |
| 115 | `4A54C265` | `157BB6C5` | `A6CC3885` | `9FDC8F05` |
| 124 | `4A54C265` | `157BB6C5` | `A6CC3885` | `9FDC8F05` |
| 130 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |
| 140 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |
| 160 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |
| 180 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |
| 240 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |
| 300 | `EC3E6705` | `157BB6C5` | `33EB4655` | `6278CDA5` |

The `WAIT` hash changes to the all-zero value `EC3E6705` immediately after the
124.024578-second frame erase and remains clear.  `STATUS` is unchanged because
the erase ends at exclusive Y boundary 480.  No rasterop intersects either
rectangle; the change is solely the documented scroll-erase operation.

No DC323 command or palette write occurs after 124.319642 seconds.  The stable
success-region hashes prove that the panel and copyright bitmap data persist
through 300 seconds.  Screenshots that omit them at 140, 180, or 300 seconds
are therefore a render/snapshot presentation discrepancy, not a raster erase.

## Keyboard transition and status line

A separate ROM-driven keyboard run posted Tab at 130 seconds, Tab again at
140 seconds, and `a` at 150 seconds.  CPU1 read the native LK201 scan code
`D4` for both Tab presses (including typematic repeats) and `C2` for `a` at
SBUF-read PC `A2FD`.  The first Tab caused 226 DC323 command writes and changed
the `STATUS` bitmap hash from `157BB6C5` to `29FCD365`.  Neither the second Tab
nor `a` caused another graphics command or changed that hash.

This is expected terminal behavior, not a stuck clear.  The DEC pocket service
guide explicitly defines the twenty-fifth display row as the status line, and
its Set-Up screen example includes `Printer: None` on that row.  After the
first key enters normal terminal operation, ordinary keys are host input; they
do not toggle or erase the persistent local status row.  The trace is produced
by `graphics-keyboard-status-trace.lua` and uses no injected display operation.

## Documentation basis

- *Dragon Video System Hardware Specification*, section 3.5.1, page 30:
  every rasterop has a destination and may have zero, one, or two sources; zero
  sources imply a constant source.
- The same specification, section 4.1.2.2, page 88: command bits S2E and S1E
  independently enable the memory sources while destination enable remains set.
- The same specification, register 14 description on page 74: loading the Y
  scroll constant schedules the following frame, and bit 13 erase mode clears
  the complete scroll region to the Viper fill color regardless of distance.
- *DEC Viper Video Processor*, Table 7: logic-function `0` produces zeros,
  function `A` selects source, bit 6 selects source versus complement, and
  registers 8/9 provide the programmable masks.
- Viper register A is the source word used by the logic unit.
- *VT340 Pocket Service Guide*, overview and Set-Up example: the twenty-fifth
  display row is the status line, and `Printer: None` is normal status content.

## Remaining boundary

The missing bitmap erase is resolved.  The remaining intermittent blank
success screenshots are downstream presentation/snapshot behavior: the
POST_OK and COPYRIGHT bitmap hashes stay constant while captured output
alternates.  That issue must not be addressed by replaying raster commands or
redrawing firmware strings.

Destination-enabled source-2 rasterops, linear-pattern mode, non-erase scroll
execution, and full plane/chip-select semantics remain explicitly
unimplemented.  None was added or inferred from this trace.  Two
destination-disabled diagnostic command words have source-2 bits set; they do
not request bitmap updates.
