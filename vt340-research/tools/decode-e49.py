#!/usr/bin/env python3
"""Render the VT340 E49 ROM according to its schematic address wiring.

The output is a portable graymap showing all 128 byte-wide columns for each
combination of the seven low VAD lines and the VAD9 bank line.  It deliberately
does not claim how the omitted VAD7/VAD8 signals are generated; it is an aid
for establishing the physical ROM organization from the dumped data.
"""

from pathlib import Path
import sys


def e49_address(byte_column: int, vad_row: int) -> int:
    """Map latched ADD0-4/6-7 and VAD0-6/9 to E49 (schematic sheet 28)."""
    return e49_signal_address(vad_row, byte_column)


def e49_signal_address(vad: int, add: int) -> int:
    """Map the actual 11-bit VAD and 8-bit multiplexed ADD signals."""
    address = ((add >> 7) & 1) << 9          # ADD7 -> A9
    address |= ((add >> 6) & 1) << 8         # ADD6 -> A8
    address |= ((add >> 4) & 1) << 7         # ADD4 -> A7
    address |= ((add >> 3) & 1) << 6         # ADD3 -> A6
    address |= ((add >> 2) & 1) << 5         # ADD2 -> A5
    address |= ((add >> 1) & 1) << 4         # ADD1 -> A4
    address |= (add & 1) << 3                # latched ADD0 -> A3
    address |= vad & 0x07                    # VAD0-2 -> A0-2
    address |= ((vad >> 3) & 0x07) << 11     # VAD3-5 -> A11-13
    address |= ((vad >> 6) & 0x01) << 10     # VAD6 -> A10
    address |= ((vad >> 9) & 0x01) << 14     # VAD9 -> A14
    return address


def adder_addresses(x: int, y: int) -> tuple[int, int]:
    """Return DC323 row/column outputs for XCON 014d (8-bit, >512 mode)."""
    row_sources = ((y, 12), (y, 10), (x, 10), (y, 4), (y, 3), (x, 8),
                   (y, 2), (y, 1), (y, 0), (x, 7), (x, 6))
    column_sources = ((y, 11), (y, 9), (x, 11), (x, 9), (y, 5), (y, 8),
                      (y, 7), (y, 6), (x, 5), (x, 4), (x, 3))
    row = sum(((value >> bit) & 1) << (10 - index)
              for index, (value, bit) in enumerate(row_sources))
    column = sum(((value >> bit) & 1) << (10 - index)
                 for index, (value, bit) in enumerate(column_sources))
    return row, column


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(f"usage: {sys.argv[0]} E49.bin OUTPUT.pgm "
              "[atlas|wiring|transpose|logical-column|logical-row]", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).read_bytes()
    if len(source) != 0x8000:
        raise ValueError(f"expected a 32768-byte 27256 image, got {len(source)}")

    layout = sys.argv[3] if len(sys.argv) == 4 else "atlas"
    if layout not in ("atlas", "wiring", "transpose", "logical-column", "logical-row"):
        raise ValueError(f"unsupported layout {layout!r}")
    if layout == "atlas":
        width, height = 256, 1024
        pixels = bytearray(width * height)
        for y in range(height):
            for x in range(width):
                value = source[(y << 5) | (x >> 3)]
                # E49 O0 is the leftmost pixel in each source byte.
                pixels[y * width + x] = 255 if value & (1 << (x & 7)) else 0
        Path(sys.argv[2]).write_bytes(f"P5\n{width} {height}\n255\n".encode() + pixels)
        return 0
    transpose = layout == "transpose"
    if layout.startswith("logical-"):
        width = height = 512
        pixels = bytearray(width * height)
        for y in range(height):
            for x in range(width):
                row, column = adder_addresses(x, y)
                # The external ADD latch and live VAD pins expose the two
                # multiplexed DRAM address phases simultaneously to E49.
                vad, add = ((column, row) if layout == "logical-column" else (row, column))
                value = source[e49_signal_address(vad, add)]
                pixels[y * width + x] = 255 if value & (0x80 >> (x & 7)) else 0
        Path(sys.argv[2]).write_bytes(f"P5\n{width} {height}\n255\n".encode() + pixels)
        return 0

    width, height = ((256 * 8, 128) if transpose else (128 * 8, 256))
    pixels = bytearray(width * height)
    for vad in range(256):
        for add in range(128):
            value = source[e49_address(add, vad)]
            for bit in range(8):
                x, y = ((vad * 8 + bit, add) if transpose else (add * 8 + bit, vad))
                pixels[y * width + x] = 255 if value & (0x80 >> bit) else 0

    Path(sys.argv[2]).write_bytes(f"P5\n{width} {height}\n255\n".encode() + pixels)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
