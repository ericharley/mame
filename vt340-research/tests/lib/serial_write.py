#!/usr/bin/env python3
"""Write a file to a PTY with bounded host-side pacing."""

import argparse
import os
import time
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("endpoint")
parser.add_argument("input", type=Path)
parser.add_argument("--baud", type=int, default=19200,
                    help="host pacing rate; one start, eight data, and one stop bit per byte")
args = parser.parse_args()

delay = 10.0 / args.baud
descriptor = os.open(args.endpoint, os.O_WRONLY)
try:
    for value in args.input.read_bytes():
        os.write(descriptor, bytes((value,)))
        time.sleep(delay)
finally:
    os.close(descriptor)
