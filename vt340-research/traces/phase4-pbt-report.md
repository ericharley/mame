# Phase 4 command-32 PBT and visible POST report

## Result

The rows of `4` glyphs were an emulator artifact, not text requested by either
CPU. CPU2 command-32 handler `db98` performs a documented DC323
bitmap-to-processor transfer (PBT) from E49 before constructing the persistent
POST screen. The driver treated DC323 register 7 as a readable command latch,
so all 1,024 FIFO reads returned the previously written CSR value `34`.
CPU2 faithfully copied those bytes into its text buffer and later rendered
them as character code `34`.

The driver now implements this E49 PBT as a real sequential register-7 FIFO
read. Original firmware consequently renders its actual POST result strings.
No display string or raster command is injected.

## Firmware path

At 121.691819 seconds CPU2 enters `db98`, calls the E5 initialization routine,
then reaches E4 routine `bd07`. The relevant setup is:

| Operation | Value | Meaning |
|---|---:|---|
| I/D data register 7 | `0034` | Viper CSR4 value: internal source load, I/D output, delay enabled |
| I/D command register 8 | `0194` | load Viper CSR4 |
| source X/Y | `0000` / `12e4` | E49 byte stream beginning at ROM offset `5c80` |
| fast/slow extent | `0100` / `0020` | 256 by 32 pixels = 1,024 eight-bit transfers |
| command register 8 | `0bc4` | source-1 bitmap-to-processor transfer |

`bbae-bbb7` polls DC323 status bit 5 (I/D Data Receive Ready). Each iteration
then reads register 7 at `bd2f` and stores the byte into `cc00-cfff`.

The Dragon specification defines register 7 as a six-word I/D FIFO. It is not
a retained copy of the last word written. In eight-bit mode, each read on this
path returns eight E49 pixels, which are one byte of the ROM stream.

## Failing and corrected data

Before the correction:

```text
DC323 register 7: 34 34 34 34 ... (1,024 times)
CPU2 CC00-CFFF:   34 34 34 34 ...
first glyphs:     34 34 34 34 ...
```

After the correction:

```text
DC323 register 7 first/last: 57 / FF
CPU2 CCC0-CCCF: 56 54 33 00 30 20 4F 4B 45 72 72 6F 72 20 2D 19
decoded:         VT3\0 0 OK Error - ...
first glyphs:    56 54 33 34 30 ...
```

The source is directly visible in E49 at offsets `5c80-607f`. Offset `5c80`
begins with `Wait`; offset `5d40` contains the English `VT340 OK` and POST
error strings. This independently matches the transfer origin and length.

## Current visible state

CPU1 submits command 32 with result byte `63`. A write-level trace of internal
RAM `1f` establishes its provenance:

| Time (s) | Writer / test path | Transition |
|---:|---|---:|
| 119.996769 | CPU1 `3c0c` | `00 -> 01` |
| 120.022644 | CPU1 `3d4e` | remains `01` |
| 120.621000 | CPU1 `4378` | `01 -> 03` |
| 120.849180 | CPU1 `438a` | `03 -> 23` |
| 120.886056 | CPU1 `f729` | `23 -> 63` |
| 121.580280 | mailbox result OR at `4270` | remains `63` |

The corrected persistent screen therefore reads:

```text
VT340 NVR Error - 1
VT340 Comm 1 Port Data Error - 2
VT340 Comm 2 DEC-423 Data Error - 6
VT340 Printer Port Error - 7
```

This is forward progress: the original firmware now leaves `Wait`, reads its
localized message data through the documented hardware mechanism, and renders
specific POST failures. Reaching `VT340 OK` now requires resolving the four
hardware-test bits in CPU1 result `63`, not further display work.

## Reproduction

- `phase4-pbt-provenance.lua` records the command/register state, FIFO count,
  copied bytes, and transfer endpoints.
- `phase4-cpu1-post-result.lua` records every result-byte writer.
- `phase4-visible-raster.lua` proves that the corrected bytes become original
  firmware glyph requests.
- `tests/phase4-pbt-transfer.sh` verifies the 1,024-byte E49 transfer and the
  `VT340 OK` source record at `ccc0`.
