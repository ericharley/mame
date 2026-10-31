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
frame.  With CPU1's later serial-service stack also stable, the authentic path
continues to display `Wait`.  The remaining blocker is now the missing firmware
state transition, not POST restart or ring corruption.

A command-level trace now separates the missing banner from the raster
engine.  Before entering the interrupt-enabled E4 loop, firmware performs a
large series of `0ed0` E49 transfers beyond the programmed refresh limits
(`XL=0340`, `YL=020a`).  These initialize off-screen backing storage, not the
800x500 scanout.  The four proven `Wait` glyphs are the persistent visible
result on the repaired native dispatcher path.  The accompanying destination-only commands use
logic function `cc` (destination) or clear a line at Y=`020a`, so they do not
contain a hidden `VT340 OK` image.  No normal-operation PBT command is issued.
The banner is therefore absent upstream of the implemented raster path rather
than being drawn and lost by an incorrect viewport or an ignored source-2/fill
operation.

The DC323 register trace also confirms zero final Y offset, zero pending/new/
old indexes, zero scroll constants, and refresh limits `0340/020a`.  Scanout
from bitmap origin zero remains correct for this boot path.
