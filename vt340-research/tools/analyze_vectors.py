#!/usr/bin/env python3
"""Show 8051 architectural vector bytes and definite long-jump targets."""

from __future__ import annotations

import argparse
from pathlib import Path

VECTORS = ((0x0000, "reset"), (0x0003, "INT0"), (0x000B, "timer0"),
           (0x0013, "INT1"), (0x001B, "timer1"), (0x0023, "serial"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("roms", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.roms:
        data = path.read_bytes()
        print(path)
        for address, name in VECTORS:
            chunk = data[address:address + 8]
            decoded = ""
            if len(chunk) >= 3 and chunk[0] == 0x02:
                decoded = f"LJMP {chunk[1] << 8 | chunk[2]:04X}"
            print(f"  {address:04X} {name:7s} {chunk.hex(' '):23s} {decoded}")


if __name__ == "__main__":
    main()
