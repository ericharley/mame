# Video hardware

## DC323 Adder register block

The mirrored `f?00-f?3f` register block belongs to E70, the DC323 Adder, not
the E36 DC7051 timing generator.  DEC's *Dragon Video System Hardware
Specification* gives names and semantics that match the VT340 firmware writes
exactly:

| Register | Name | Observed VT340 use |
| --- | --- | --- |
| `08` | duplicate command address | `0ec0` starts a source-1/destination rasterop |
| `09` | mode | `0080`: normal mode, no indexing, pen down |
| `22`, `23` | source 1 X/Y origin | character-ROM source position |
| `24`, `25` | destination X/Y origin | screen position |
| `26` | fast destination DX | character width (`000a`, ten pixels) |
| `29` | slow destination DY | character height (`0014`, twenty pixels) |
| `2a`, `2b` | fast/slow scale | unity scaling in the text path |
| `35` | X scan configuration | `014d`: 8-bit bus, 512-1024 mode, 13 major reads |

The low six bits of XCON are the major reads per scan.  In 8-bit mode each
major read supplies 64 pixels, so `014d` establishes a physical scan width of
13 * 64 = 832 pixels.  The configured MAME screen exposes the observed 800
active pixels from that scan.

Register 3 is a read-status/write-clear register during normal operation.
Dragon defines bit 0 as Pause Complete and bit 1 as Scroll Service; both are
sticky at the vertical frame boundary, gated onto the interrupt output by the
matching register-2 enable bits, and cleared when firmware writes a zero to
the status bit. CPU2 routine `1bd2` uses this contract to wait for and
acknowledge eight Pause Complete events. Bits 2-5 report the previously
documented raster/address/I-D completion conditions.

The operational interrupt dispatcher uses the same contract. At `0047`, a
set bit 0 selects the `fe` acknowledgement, clearing Pause Complete. A
remaining bit 1 causes one level-triggered re-entry and the `fd`
acknowledgement clears Scroll Service. The former PC-qualified inversion of
bit 0 forced both entries down the `fd` path, left Pause Complete asserted,
and starved CPU2's packet dispatcher. It has been removed; repeated cold boots
now drain every startup ring packet through the original CPU2 firmware.

The first observed text rasterops have been decoded from the E4 firmware and
runtime register stream.  Later synchronized POST work showed that the
resulting `Wait` display belongs to the delayed-status/failure path rather than
the normal idle screen.  The source origins encode the character code as a
16-column, 20-scan atlas:

```
source_x = (character & 0x0f) * 16
source_y = 0x1000 + (character >> 4) * 20
```

The first four operations spell `Wait`, with destination origins `(0,0)`,
`(10,0)`, `(20,0)`, and `(30,0)`.  They remain useful proof of the character
source and raster path, but are no longer treated as proof of normal POST exit.

## E49 character ROM

E49 is a 32 KiB 27256 selected as off-screen source bitmap storage.  Schematic
sheet 28 establishes its address pins:

| E49 | Signal | E49 | Signal |
| --- | --- | --- | --- |
| A14 | VAD9 | A6 | ADD3 |
| A13 | VAD5 | A5 | ADD2 |
| A12 | VAD4 | A4 | ADD1 |
| A11 | VAD3 | A3 | latched ADD0 |
| A10 | VAD6 | A2 | VAD2 |
| A9 | ADD7 | A1 | VAD1 |
| A8 | ADD6 | A0 | VAD0 |
| A7 | ADD4 | | |

XCON `014d` selects the DC323's documented 8-bit, 512-1024 row/column address
permutation.  E49 combines the live VAD outputs with the externally latched,
multiplexed ADD bus so its contents appear as a bitmap source during a normal
rasterop.  Substitution of those signals into the schematic pinout reduces to
the conventional bitmap address below; E49 O0 is the leftmost pixel in a byte.

```
address = (source_y & 0x03ff) * 32 + ((source_x & 0x00ff) / 8)
pixel   = BIT(E49[address], source_x & 7)
```

`tools/decode-e49.py` renders this 256-pixel-wide atlas directly.  Its decoded
glyphs reproduce the known VT340 10x20 font, including the first firmware
string `Wait`.

## Bitmap and scanout

Four DC322 Vipers drive the bitmap planes.  Each displayed pixel is formed by
four serial plane bits indexing a 16-entry RGB color map; each color-map entry
has four bits each of red, green, and blue. Each Viper now retains its own
register set. Schematic sheet 8 shows E16 decoding `f060-f07f` as `CNTLWR`; a
74LS174 latches CPU2 write-data bits `BAD3-BAD0` as `V0CS-V3CS`; `BAD5`
separately drives `OPADDS`. The driver uses that physical select mask for both
Viper register loads and raster destination writes.

For the proven normal text path, function value `ca` selects the source
(`F=S`). The Viper Boolean result selects that plane's foreground or
background word, and the corresponding word bit becomes the bitmap-plane
output. The `0ec0` E49-to-destination rasterop therefore writes four
independent bitmap planes rather than broadcasting one Boolean bit to all
planes. A firmware-free regression generates and verifies every color index
from 0 through 15.

The same normal-mode engine now follows the command's Viper-function selector,
mask registers, source complement control, and bitmap-to-bitmap source path.
This produces the first genuine on-screen firmware text (`Wait`) at exact
832-total/800-active by 526-total/500-active screen timing.

Normal-mode axis-aligned raster operations also apply the Dragon fast and slow
scale accumulators. This is required by the Set-Up return path: firmware uses
slow scale `0199` to replicate each off-screen session row across a 20-scanline
terminal character row. The previous unscaled copy mixed 20 adjacent backing
rows into every displayed row. Normal and linear-pattern destinations also
walk both signed fast and slow vectors with the DC323's documented Bresenham
initialization. This supplies rotated and non-axis-aligned ReGIS vectors and
text without bypassing the firmware command stream.

Schematic sheet 17 identifies the color map as E51/E52 AS870 register files.
The four serialized bitmap-plane bits select one of 16 entries; the outputs
are four bits each of red, green, and blue. PAL E16 decodes `f080-f09f` as the
E51 aperture and `f0a0-f0bf` as E52; BA4 is not decoded and the low address
nibble selects the entry. These ranges were previously misidentified as
DC7051 timing registers. E51's low data nibble is red and its high nibble is
unused. E52's high nibble drives green and its low nibble drives blue, as
confirmed by both the board drawing and native SIXEL palette loads.

The BP0 scanout drawing also establishes the bit significance at that lookup
boundary. The DC323 device stores Viper 0 as plane bit 0, but the four serial
outputs reach the E51/E52 address latch in reverse numerical significance.
Scanout therefore reverses the four-bit plane value before selecting an
output-map entry. Without that translation, firmware color `n` displayed
entry `bitswap(n)`; only `0`, `6`, `9`, and `15` selected themselves. That
exact four-entry set was independently observed in the native Color Set-Up
preview before the correction.

The driver retains both apertures and displays every completely programmed
entry as genuine 12-bit RGB. Entries without both halves retain a monochrome
visibility fallback rather than an invented color. The native `VT340 OK`
screen itself programs monochrome plane values, so its unchanged black-and-
white appearance is not evidence that the four-plane path is inactive.

The service guide establishes that a successful power-up is not a black idle
screen: it displays `VT340 OK` in a rectangle together with the firmware
revision and copyright message.  The observed blank-glyph/logic-`81` sweep is
therefore only one intermediate display operation.  CPU1 now passes its
destructive shared-RAM test, receives CPU2's `7ff2=80` response, and enters its
normal firmware at `4551`.  The `7e7e/7e7f` bytes have since been identified as
command-ring producer/consumer indices.  A corrupt E4 dump byte at CPU address
`92ff` has been reconstructed as `MOVX @DPTR,A`, restoring the firmware's
native packet-length store and indirect dispatcher without a synthetic stack
frame. With CPU1's later serial-service stack also stable and command-32's
register-7 PBT implemented, the authentic path now replaces `Wait` with its
persistent POST result. The remaining blocker is CPU1 result `63`, not POST
restart, ring corruption, or hidden graphics output.

A command-level trace now separates the missing banner from the raster
engine.  Before entering the interrupt-enabled E4 loop, firmware performs a
large series of `0ed0` E49 transfers beyond the programmed refresh limits
(`XL=0340`, `YL=020a`).  These initialize off-screen backing storage, not the
800x500 scanout. The four proven `Wait` glyphs are the temporary visible
result on the repaired native dispatcher path. The later command-32 handler
issues PBT command `0bc4`, with source `(0000,12e4)` and extent `0100` by
`0020`, to stream 1,024 bytes from E49 offsets `5c80-607f` through DC323
register 7 into CPU2 storage `cc00-cfff`. That range is the localized startup
string table and includes `VT340 OK`. Modeling register 7 as the documented
I/D FIFO removes the former rows of character `4` and lets original firmware
render its actual POST error screen. See `../traces/phase4-pbt-report.md`.

The DC323 register trace also confirms zero final Y offset, zero pending/new/
old indexes, zero scroll constants, and refresh limits `0340/020a`.  Scanout
from bitmap origin zero remains correct for this boot path.

## Completion status and operational PBT

The destructive DC323 bitmap diagnostic is represented as an explicit device
mode sequence rather than by recognizing the firmware routines that execute
it.  The `F072=ff` test-control write arms bitmap selection; the first
`0000=aa` write begins the AA phase.  Successful reads of `aa` and `55` at
`efff` advance to the following pattern and final verify/clear phases.  P3.5
falling supplies the documented complemented `55` test result.  The final
zero read at `ffff` makes the next external access return to normal address
decoding and enables operational DC323 status behavior.

This state sequence replaces the former checks for firmware PCs
`badb/badc/baf0/baf6/baf7`, the `1804` arming check, and the `1329` release
check.  A cold-boot regression rejects reintroduction of the five generic
memory-loop PCs.  The asymmetric boundaries are intentional: the AA and 55
write/read loops cover `0000-efff`, while the final diagnostic aperture
continues through `f000-ffff` before it is cleared.

DC323 status bits 2, 3, and 4 report Rasterop Initialization Complete,
Rasterop Complete, and Address Output Complete.  Loading a rasterop or
processor/bitmap transfer clears these conditions.  Since the current raster
engine completes a command synchronously, all three become asserted when a
rasterop returns.  This lets the native status-line drawing loop finish rather
than leaving CPU2 at `ef11` and CPU1 at the shared `4be5` barrier.

Status bit 5 follows the documented I/D Data Receive Ready condition.  A
bitmap-to-processor transfer supplies sequential eight-pixel bytes through
register 7 from either E49 or ordinary bitmap memory.  The final FIFO read
clears Data Receive Ready and asserts Address Output Complete.  The off-screen
bitmap transfer used while entering Set-Up therefore follows the same device
path as the earlier E49 startup-string transfer.  See
`../traces/setup-screen-report.md`.

## Clear/erase command audit

A complete 300-second command trace is documented in
`../traces/graphics-clear-erase-report.md`.  It identified 35 normal-mode
rasterops with destination enabled and both memory sources disabled.  Dragon
defines this as a constant-source operation; the Viper source register supplies
the constant and the selected logic function combines it with destination.
The driver now executes that documented class.  Source 2 and non-normal modes
remain unsupported.

The six late zero-source clears target `(0,522)` at `800x20` and `(0,1506)` at
`800x24`.  Both bands were already clear, so the corrected commands change no
pixels and do not erase visible `Wait`.  No post-115-second rasterop intersects
the visible `Wait` or status-line regions.

The actual erase is a separate DC323 frame operation. At 124.024578 seconds
firmware loads register 14 with `2001` after setting scroll bounds X=`0..800`,
Y=`0..480`, Y offset zero, and Viper fill zero. Dragon defines bit 13 as erase
mode: the following frame clears the complete scroll region to the fill color.
The driver now executes that one-shot frame-boundary operation. The visible
`Wait` hash changes to the all-zero value while the status line, outside the
exclusive Y=480 boundary, is preserved.

## Normal text scrolling

A paced Comm 1 stream that fills the terminal screen establishes the native
line-scroll sequence. CPU2 loads DC323 register 14 with `0014` once per row:
20 pixels upward in normal-scroll mode. The active device-coordinate bounds
are X=`4..804`, Y=`0..480`, Y offset is zero, and the Viper fill word is zero.
Loading the constant schedules the operation for the following vertical frame.

The driver now moves all four bitmap planes upward inside those exclusive
bounds and fills the exposed bottom band from the Viper fill word. Downward
requests use the inverse copy order so overlapping source rows are retained.
The status line begins at Y=480 and is therefore not moved.

The Adder X boundaries identify the first and last bitmap words involved;
the Viper left/right boundary registers select individual pixels in those
edge words. For the terminal's 8-bit Viper bus, normal line scrolling uses
Adder X=`4..804`, left mask `00`, and right mask `ff`. The resulting effective
pixel range is X=`0..799`: all eight pixels in the first byte participate and
none in the trailing byte do. Treating the Adder values as literal pixel
bounds left X=`0..3` stationary and produced a growing artifact in the first
character column. The scroll engine now combines the Adder word range with
the Viper edge masks, including the documented 4-, 8-, and 16-bit bus widths.

The firmware redraws the newly exposed band with DC323 X-control value `00c0`:
normal mode, pen down, and destination indexing enabled. All six pending/new/
old index registers are zero on this verified terminal path. The former exact
`0080` check rejected every `00c0` rasterop, which made the old lines move but
left new rows blank or fragmentary. Normal rasterops now accept the documented
index-enable control bits; the zero indexes make their addresses identical to
the unindexed form. A 40-line paced serial run produces 17 native scroll
requests and leaves lines 18 through 40 visible in order while preserving the
status row. `../traces/scroll-command-trace.lua` records the register sequence
and captures before/after screenshots without modifying emulated state.

Direct framebuffer hashes also show that the success panel and copyright
bitmap persist unchanged from 130 through 300 seconds; intermittent blank
snapshots are in the presentation path, not the bitmap raster engine.

## SIXEL integration workload

`tests/sixel-bill.sh` supplies the reproducible 16-color 330 by 440 Bill the
Cat image to Comm 1 after leaving the POST screen through the native LK201
path. The exact PNG, converter, and 93,198-byte SIXEL stream are retained in
`fixtures` and `tools`. The test uses a raw pseudo-terminal with XON/XOFF, the
same external path as a macOS/getty session.

The DC323 now executes X-mode processor-to-bitmap transfers, including the
six-word FIFO-facing data path used for each 1 by 6 SIXEL column. Processor
words follow the selected Viper CSR's external-load setting (source, both
masks, mask 2, or none), and the resulting destination cycle observes the
selected logic function, masks, foreground/background words, bus width, and
edge masks. The firmware-free device regression covers the native 1 by 6
form, unaligned leading/trailing words, completion status, and CSR mask loads.

The firmware color decision is also native. EEPROM configuration byte `5a`
loads into shared state `4c00`; bit 4 clear selects monochrome output-map
tables and bit 4 set selects color. The recovered EEPROM contains the valid
saved value `28`, meaning Color Map: monochrome. With the complete VT340 model
identity exposed, Global Set-Up contains the documented Color Map row. The
LK201-only `color-setup-trace.lua` changes the working value from `28` to `38`
without a RAM write, firmware patch, or palette injection.

A raw PTY run using that native selection received all 93,198 SIXEL bytes with
zero byte mismatches and balanced 901-pair XON/XOFF flow control. It programmed
all 16 output-map entries and rendered the complete orange/yellow Bill image.
Example entry 11 is E51=`ae`, E52=`81`, which decodes to RGB `ee8811`. The
command path contains no synthetic SIXEL parser or framebuffer injection.

`tests/sixel-bill-pty.sh` implements that end-to-end color acceptance path and
`tests/sixel-bill.sh` is its conventional entry point. The bitbanger's shared
bidirectional file transport is deliberately not used as the visual authority.
Earlier PTY attempts intermittently left DCS mode, so repeated cold-boot runs
remain worthwhile. The trace now compares every CPU-visible byte with the
fixture and reports the first mismatch if transport corruption recurs.

E51/E52 color-map writes become active whenever their decoded hardware
aperture is written. The former requirement that CPU2 interrupts be enabled
and that the DC323 had already drawn a visible glyph was a display-policy
heuristic with no corresponding board gate; it could leave legitimate SIXEL
palette entries on the monochrome fallback.
