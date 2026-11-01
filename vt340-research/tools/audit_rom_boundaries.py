#!/usr/bin/env python3
"""Audit and reproduce the VT340 Arduino EPROM-dump reconstruction."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rom:
    name: str
    seed: int


ROMS = (Rom("e1", 0x07), Rom("e2", 0x08), Rom("e3", 0x07),
        Rom("e4", 0x08), Rom("e5", 0x09))
EXPECTED = {
    "e1": (124, 0x8E),
    "e2": (121, 0x77),
    "e3": (125, 0x62),
    "e4": (125, 0xEB),
    "e5": (118, 0x6E),
}
ANCHORS = {
    "e1": {0x38FF: 0x78},
    "e2": {0x3BFF: 0x1F},
    "e3": {0x14FF: 0xE5, 0x15FF: 0x22, 0x28FF: 0xE0,
           0x30FF: 0x80, 0x48FF: 0x75},
    "e4": {0x12FF: 0xF0, 0x622D: 0x02},
    "e5": {0x72FF: 0x09},
}


def rotate_left(value: int) -> int:
    return ((value << 1) | (value >> 7)) & 0xFF


def reconstruct(raw: bytes, rom: Rom) -> tuple[bytearray, int]:
    if len(raw) != 0x8000:
        raise ValueError(f"{rom.name}: expected 32768 bytes, got {len(raw)}")

    image = bytearray(raw[1:])
    image.append(0)
    shifted = bytes(image)

    # Raw xx00 preserves logical xxFF for pages 01 through 7e.  Logical
    # 00ff has no preserved pre-transition sample, and 7fff was never read.
    for page in range(1, 0x7F):
        image[(page << 8) | 0xFF] = raw[page << 8]

    if rom.name == "e4":
        image[0x622D] = 0x02

    changed_boundaries = sum(
        image[(page << 8) | 0xFF] != shifted[(page << 8) | 0xFF]
        for page in range(1, 0x7F)
    )

    checksum = rom.seed
    for value in image[:-1]:
        checksum = rotate_left(value) ^ checksum
    image[-1] = ((checksum >> 1) | (checksum << 7)) & 0xFF
    return image, changed_boundaries


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rompath", type=Path, default=Path("roms/vt340"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    print("ROM recoverable changed first-unknown checksum-tail")
    failures: list[str] = []
    for rom in ROMS:
        raw = (args.rompath / f"{rom.name}.bin").read_bytes()
        image, changed = reconstruct(raw, rom)
        checksum = rom.seed
        for value in image:
            checksum = rotate_left(value) ^ checksum

        print(f"{rom.name.upper()} 126 {changed} "
              f"{image[0x00ff]:02x} {image[0x7fff]:02x}")
        expected_changed, expected_tail = EXPECTED[rom.name]
        if changed != expected_changed:
            failures.append(f"{rom.name}: changed {changed}, expected {expected_changed}")
        if image[0x7FFF] != expected_tail:
            failures.append(
                f"{rom.name}: tail {image[0x7fff]:02x}, expected {expected_tail:02x}")
        if checksum:
            failures.append(f"{rom.name}: checksum result {checksum:02x}")
        for address, expected in ANCHORS[rom.name].items():
            if image[address] != expected:
                failures.append(
                    f"{rom.name}:{address:04x}={image[address]:02x}, expected {expected:02x}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        if args.check:
            raise SystemExit(1)
    elif args.check:
        print("VT340 ROM boundary reconstruction audit passed")


if __name__ == "__main__":
    main()
