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
has four bits each of red, green, and blue.  The current driver retains the
four Viper logic-function registers loaded by commands `0184-0187`.  For the
proven normal text path, function value `ca` selects the source (`F=S`), and
the `0ec0` E49-to-destination rasterop writes four independent bitmap planes.
The same normal-mode engine now follows the command's Viper-function selector,
mask registers, source complement control, and bitmap-to-bitmap source path.
This produces the first genuine on-screen firmware text (`Wait`) at exact
832-total/800-active by 526-total/500-active screen timing.  Until color-map
programming is decoded, index zero is displayed black and nonzero plane data
is displayed monochrome; no guessed RGB palette is stored.

Schematic sheet 17 identifies the color map as E51/E52 AS870 register files.
The four serialized bitmap-plane bits select one of 16 entries; the outputs
are four bits each of red, green, and blue.  PAL E16 decodes `f04x` as the E51
write aperture and `f05x` as the E52 aperture, with the address low nibble
selecting the entry.  E51's low data nibble is red (its high nibble is unused);
E52's low nibble is green and high nibble is blue.  The driver now retains
both apertures and displays an entry as genuine 12-bit RGB once firmware has
written both halves after entering visible normal operation.  Earlier writes
belong to graphics POST: its destructive `aa`, zero, and register-pattern
sweeps leave diagnostic residue that is not a normal display palette.  Those
values are retained for register behavior but deliberately do not color the
screen.  Unprogrammed operational entries remain on the monochrome visibility
fallback rather than receiving an invented color.

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

Direct framebuffer hashes also show that the success panel and copyright
bitmap persist unchanged from 130 through 300 seconds; intermittent blank
snapshots are in the presentation path, not the bitmap raster engine.
