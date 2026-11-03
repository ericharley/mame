#!/usr/bin/env python3
"""Convert a PNG to a 16-color DEC sixel image (and an optional PNG preview)."""
import argparse
import sys
from pathlib import Path
from PIL import Image, ImageOps

ESC = b'\x1b'


def run_length_encode(chars):
    """Encode a sixel scanline with DEC !<count><character> repeats."""
    result = []
    i = 0
    while i < len(chars):
        j = i + 1
        while j < len(chars) and chars[j] == chars[i]:
            j += 1
        count = j - i
        if count >= 4:
            result.append(f'!{count}{chars[i]}')
        else:
            result.append(chars[i] * count)
        i = j
    return ''.join(result)


def sixel_encode(image):
    """Encode an indexed ('P') Pillow image to one complete sixel DCS sequence."""
    if image.mode != 'P':
        raise ValueError('Expected a palette-indexed image')
    width, height = image.size
    palette = image.getpalette()[:48]
    pixels = image.load()

    # DCS P1;P2;P3 q: P2=1 requests transparent background behavior.
    # The image still paints all pixels, so this also works with opaque images.
    parts = ['\x1bP0;0;0q', f'"1;1;{width};{height}']
    for color in range(16):
        r, g, b = palette[color * 3:color * 3 + 3]
        parts.append(f'#{color};2;{round(r * 100 / 255)};{round(g * 100 / 255)};{round(b * 100 / 255)}')

    for y in range(0, height, 6):
        used = sorted({pixels[x, yy] for yy in range(y, min(y + 6, height)) for x in range(width)})
        for index, color in enumerate(used):
            if index:
                parts.append('$')  # rewind horizontal position within band
            chars = []
            for x in range(width):
                bits = 0
                for bit in range(6):
                    if y + bit < height and pixels[x, y + bit] == color:
                        bits |= 1 << bit
                chars.append(chr(63 + bits))
            # Trim only trailing empty columns; no colored pixels are lost.
            while chars and chars[-1] == '?':
                chars.pop()
            parts.append(f'#{color}')
            parts.append(run_length_encode(chars))
        if y + 6 < height:
            parts.append('-')  # next six-row band
    parts.append('\x1b\\')
    return ''.join(parts).encode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path, help='Input PNG file')
    parser.add_argument('-o', '--output', type=Path, help='Sixel output (default: input.six)')
    parser.add_argument('--preview', type=Path, help='Optional quantized PNG preview')
    parser.add_argument('--width', type=int, help='Optional maximum width, preserving aspect ratio')
    parser.add_argument('--height', type=int, help='Optional maximum height, preserving aspect ratio')
    parser.add_argument('--dither', action='store_true', help='Enable Floyd-Steinberg dithering')
    parser.add_argument('--stdout', action='store_true', help='Write sixel directly to stdout')
    args = parser.parse_args()

    im = Image.open(args.input).convert('RGB')
    if args.width is not None or args.height is not None:
        if (args.width is not None and args.width <= 0) or (args.height is not None and args.height <= 0):
            parser.error('Width and height must be positive')
        im.thumbnail((args.width or im.width, args.height or im.height), Image.Resampling.LANCZOS)

    dither = Image.Dither.FLOYDSTEINBERG if args.dither else Image.Dither.NONE
    indexed = im.quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=dither)
    # Pillow can return fewer than 16 palette entries for simple images.
    palette = indexed.getpalette() or []
    indexed.putpalette((palette + [0] * 48)[:48] + [0] * (768 - 48))
    if args.preview:
        indexed.convert('RGB').save(args.preview)
    data = sixel_encode(indexed)
    if args.stdout:
        sys.stdout.buffer.write(data)
    else:
        dest = args.output or args.input.with_suffix('.six')
        dest.write_bytes(data)
        print(f'Wrote {dest} ({len(data):,} bytes, {im.width}x{im.height}, 16-color palette)', file=sys.stderr)
        if args.preview:
            print(f'Wrote preview {args.preview}', file=sys.stderr)


if __name__ == '__main__':
    main()
