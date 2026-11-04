#!/usr/bin/env python3
"""Validate tracked VT340 gallery assets and their provenance manifest."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "manifest.json"
README = ROOT / "README.md"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_metadata(data: bytes) -> tuple[int, int, int]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or data[12:16] != b"IHDR":
        raise ValueError("invalid PNG")
    width, height = struct.unpack(">II", data[16:24])
    return width, height, 1


def skip_blocks(data: bytes, position: int) -> int:
    while True:
        length = data[position]
        position += 1
        if length == 0:
            return position
        position += length


def gif_metadata(data: bytes) -> tuple[int, int, int]:
    if data[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError("invalid GIF")
    width, height = struct.unpack("<HH", data[6:10])
    packed = data[10]
    position = 13
    if packed & 0x80:
        position += 3 * (1 << ((packed & 7) + 1))
    frames = 0
    while position < len(data):
        marker = data[position]
        position += 1
        if marker == 0x3b:
            break
        if marker == 0x21:
            position += 1
            position = skip_blocks(data, position)
        elif marker == 0x2c:
            frames += 1
            local_packed = data[position + 8]
            position += 9
            if local_packed & 0x80:
                position += 3 * (1 << ((local_packed & 7) + 1))
            position += 1
            position = skip_blocks(data, position)
        else:
            raise ValueError(f"unexpected GIF marker {marker:02x}")
    return width, height, frames


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    readme = README.read_text(encoding="utf-8")
    problems: list[str] = []
    declared = {entry["path"] for entry in manifest["assets"]}
    actual = {str(path.relative_to(ROOT)) for path in (ROOT / "assets").iterdir() if path.is_file()}
    if declared != actual:
        problems.append(f"asset inventory differs: undeclared={sorted(actual - declared)}, missing={sorted(declared - actual)}")
    for entry in manifest["assets"]:
        path = ROOT / entry["path"]
        if not path.is_file():
            continue
        data = path.read_bytes()
        try:
            metadata = gif_metadata(data) if path.suffix == ".gif" else png_metadata(data)
        except (IndexError, ValueError) as error:
            problems.append(f"{entry['path']}: {error}")
            continue
        expected = (entry["width"], entry["height"], entry["frames"])
        if metadata != expected:
            problems.append(f"{entry['path']}: metadata {metadata}, expected {expected}")
        observed_hash = sha256(path)
        if observed_hash != entry["sha256"]:
            problems.append(f"{entry['path']}: SHA-256 {observed_hash}, expected {entry['sha256']}")
        if f"({entry['path']})" not in readme:
            problems.append(f"{entry['path']}: not linked from README.md")
    if problems:
        for problem in problems:
            print(f"VT340 gallery error: {problem}")
        return 1
    print(f"VT340 gallery passed: {len(declared)} assets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
