#!/usr/bin/env python3
"""Create a small animated GIF from MAME RGB/RGBA PNG screenshots.

The gallery intentionally has no ImageMagick/ffmpeg dependency.  This decoder
supports the 8-bit, non-interlaced RGB/RGBA/indexed PNGs emitted by MAME and
requires the combined animation palette to contain at most 256 colors.
"""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    diagonal_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= diagonal_distance:
        return left
    return above if above_distance <= diagonal_distance else upper_left


def read_png(path: Path) -> tuple[int, int, list[tuple[int, int, int]]]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path}: not a PNG")
    position = len(PNG_SIGNATURE)
    compressed = bytearray()
    palette: list[tuple[int, int, int]] = []
    header = None
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"PLTE":
            palette = [tuple(payload[index:index + 3]) for index in range(0, len(payload), 3)]
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if header is None:
        raise ValueError(f"{path}: missing IHDR")
    width, height, depth, color_type, compression, filtering, interlace = header
    if depth != 8 or compression != 0 or filtering != 0 or interlace != 0:
        raise ValueError(f"{path}: unsupported PNG format")
    channels = {2: 3, 3: 1, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError(f"{path}: unsupported PNG color type {color_type}")
    raw = zlib.decompress(bytes(compressed))
    stride = width * channels
    rows: list[bytearray] = []
    offset = 0
    prior = bytearray(stride)
    for unused_y in range(height):
        filter_type = raw[offset]
        source = raw[offset + 1:offset + 1 + stride]
        offset += stride + 1
        row = bytearray(stride)
        for index, value in enumerate(source):
            left = row[index - channels] if index >= channels else 0
            above = prior[index]
            upper_left = prior[index - channels] if index >= channels else 0
            if filter_type == 0:
                result = value
            elif filter_type == 1:
                result = value + left
            elif filter_type == 2:
                result = value + above
            elif filter_type == 3:
                result = value + ((left + above) // 2)
            elif filter_type == 4:
                result = value + paeth(left, above, upper_left)
            else:
                raise ValueError(f"{path}: unsupported PNG filter {filter_type}")
            row[index] = result & 0xff
        rows.append(row)
        prior = row
    pixels: list[tuple[int, int, int]] = []
    for row in rows:
        if color_type == 3:
            pixels.extend(palette[index] for index in row)
        else:
            pixels.extend(tuple(row[index:index + 3]) for index in range(0, len(row), channels))
    return width, height, pixels


def lzw(indices: bytes, minimum_size: int) -> bytes:
    clear = 1 << minimum_size
    end = clear + 1
    table = {bytes((value,)): value for value in range(clear)}
    next_code = end + 1
    code_size = minimum_size + 1
    bit_buffer = 0
    bit_count = 0
    encoded = bytearray()

    def emit(code: int) -> None:
        nonlocal bit_buffer, bit_count
        bit_buffer |= code << bit_count
        bit_count += code_size
        while bit_count >= 8:
            encoded.append(bit_buffer & 0xff)
            bit_buffer >>= 8
            bit_count -= 8

    emit(clear)
    word = bytes((indices[0],)) if indices else b""
    for value in indices[1:]:
        symbol = bytes((value,))
        candidate = word + symbol
        if candidate in table:
            word = candidate
            continue
        emit(table[word])
        if next_code < 4096:
            table[candidate] = next_code
            next_code += 1
            # The decoder adds the matching dictionary entry when it consumes
            # the following code, so the encoder changes width one allocation
            # later than its own table reaches the boundary.
            if next_code > (1 << code_size) and code_size < 12:
                code_size += 1
        else:
            emit(clear)
            table = {bytes((entry,)): entry for entry in range(clear)}
            next_code = end + 1
            code_size = minimum_size + 1
        word = symbol
    if word:
        emit(table[word])
    emit(end)
    if bit_count:
        encoded.append(bit_buffer & 0xff)
    return bytes(encoded)


def sub_blocks(data: bytes) -> bytes:
    result = bytearray()
    for position in range(0, len(data), 255):
        block = data[position:position + 255]
        result.append(len(block))
        result.extend(block)
    result.append(0)
    return bytes(result)


def write_gif(output: Path, frames: list[Path], delay_ms: int, last_delay_ms: int) -> None:
    decoded = [read_png(frame) for frame in frames]
    width, height = decoded[0][:2]
    if any(frame_width != width or frame_height != height for frame_width, frame_height, unused in decoded):
        raise ValueError("all animation frames must have identical dimensions")
    colors = sorted({color for unused_width, unused_height, pixels in decoded for color in pixels})
    if len(colors) > 256:
        raise ValueError(f"combined animation palette has {len(colors)} colors; maximum is 256")
    table_entries = max(2, 1 << math.ceil(math.log2(max(2, len(colors)))))
    minimum_size = max(2, int(math.log2(table_entries)))
    color_index = {color: index for index, color in enumerate(colors)}
    result = bytearray(b"GIF89a")
    result.extend(struct.pack("<HH", width, height))
    result.extend(bytes((0x80 | 0x70 | (int(math.log2(table_entries)) - 1), 0, 0)))
    for color in colors:
        result.extend(color)
    result.extend(b"\x00\x00\x00" * (table_entries - len(colors)))
    result.extend(b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00")
    for frame_number, (unused_width, unused_height, pixels) in enumerate(decoded):
        delay = last_delay_ms if frame_number == len(decoded) - 1 else delay_ms
        result.extend(b"\x21\xf9\x04\x04")
        result.extend(struct.pack("<H", max(1, round(delay / 10))))
        result.extend(b"\x00\x00")
        result.extend(b"\x2c\x00\x00\x00\x00")
        result.extend(struct.pack("<HH", width, height))
        result.append(0)
        indices = bytes(color_index[pixel] for pixel in pixels)
        result.append(minimum_size)
        result.extend(sub_blocks(lzw(indices, minimum_size)))
    result.append(0x3b)
    output.write_bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("frames", nargs="+", type=Path)
    parser.add_argument("--delay-ms", type=int, default=80)
    parser.add_argument("--last-delay-ms", type=int, default=1500)
    args = parser.parse_args()
    write_gif(args.output, args.frames, args.delay_ms, args.last_delay_ms)


if __name__ == "__main__":
    main()
