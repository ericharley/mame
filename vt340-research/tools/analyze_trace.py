#!/usr/bin/env python3
"""Summarize first-seen VT340 XDATA accesses from a MAME error log."""

from __future__ import annotations

import argparse
import collections
from pathlib import Path
import re
import signal

ACCESS = re.compile(r"CPU([12]) XDATA ([RW]) ([0-9A-F]{4})(?:=([0-9A-F]{2}))? \(PC=([0-9A-F]{4})\)")


def main() -> None:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()
    counts: collections.Counter[tuple[str, ...]] = collections.Counter()
    first: dict[tuple[str, ...], str] = {}
    for line in args.trace.read_text(errors="replace").splitlines():
        match = ACCESS.search(line)
        if not match:
            continue
        key = match.group(1), match.group(2), match.group(3), match.group(5)
        counts[key] += 1
        first.setdefault(key, line)
    for key, count in counts.most_common():
        print(f"{count:8d}  {first[key]}")


if __name__ == "__main__":
    main()
