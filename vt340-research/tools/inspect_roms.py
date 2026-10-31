#!/usr/bin/env python3
"""Inventory VT340 ROMs without assuming a concatenation or bank order."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import zlib

VECTORS = (0x0000, 0x0003, 0x000B, 0x0013, 0x001B, 0x0023)


def strings(data: bytes, minimum: int) -> list[dict[str, object]]:
    pattern = re.compile(rb"[ -~]{%d,}" % minimum)
    return [{"offset": match.start(), "text": match.group().decode("ascii")}
            for match in pattern.finditer(data)]


def repeated_runs(data: bytes, minimum: int = 16) -> list[dict[str, int]]:
    result = []
    start = 0
    for pos in range(1, len(data) + 1):
        if pos == len(data) or data[pos] != data[start]:
            if pos - start >= minimum:
                result.append({"offset": start, "length": pos - start,
                               "byte": data[start]})
            start = pos
    return result


def jump_target(chunk: bytes) -> str | None:
    if len(chunk) >= 3 and chunk[0] == 0x02:
        return f"LJMP {chunk[1] << 8 | chunk[2]:04X}"
    if len(chunk) >= 3 and chunk[0] == 0x12:
        return f"LCALL {chunk[1] << 8 | chunk[2]:04X}"
    if chunk and chunk[0] == 0x32:
        return "RETI"
    return None


def inspect(path: Path, minimum_string: int) -> dict[str, object]:
    data = path.read_bytes()
    counts = collections.Counter(data)
    vectors = []
    for offset in VECTORS:
        chunk = data[offset:offset + 8]
        vectors.append({"offset": offset, "bytes": chunk.hex(" "),
                        "candidate": jump_target(chunk)})
    boundaries = []
    for offset in range(0, len(data), 0x2000):
        block = data[offset:offset + 0x2000]
        boundaries.append({"offset": offset,
                           "sha1": hashlib.sha1(block).hexdigest(),
                           "initial_bytes": block[:16].hex(" ")})
    return {
        "file": str(path), "size": len(data),
        "crc32": f"{zlib.crc32(data):08x}",
        "sha1": hashlib.sha1(data).hexdigest(),
        "sha256": hashlib.sha256(data).hexdigest(),
        "initial_bytes": data[:32].hex(" "),
        "vectors": vectors,
        "byte_distribution": {f"{byte:02x}": counts[byte] for byte in range(256)},
        "printable_strings": strings(data, minimum_string),
        "repeated_runs": repeated_runs(data),
        "candidate_tables": boundaries,
    }


def parse_mapping(value: str) -> dict[str, object]:
    name, _, members = value.partition("=")
    if not name or not members:
        raise argparse.ArgumentTypeError("mapping must be NAME=FILE@ADDRESS[,FILE@ADDRESS]")
    parsed = []
    for member in members.split(","):
        filename, separator, address = member.rpartition("@")
        if not separator:
            raise argparse.ArgumentTypeError("mapping member must be FILE@ADDRESS")
        parsed.append({"file": filename, "address": int(address, 0)})
    return {"name": name, "members": parsed}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("roms", nargs="+", type=Path)
    parser.add_argument("--minimum-string", type=int, default=5)
    parser.add_argument("--mapping", action="append", default=[], type=parse_mapping,
                        help="candidate map NAME=FILE@ADDRESS[,FILE@ADDRESS]")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = {"roms": [inspect(path, args.minimum_string) for path in args.roms],
              "candidate_mappings": args.mapping}
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
