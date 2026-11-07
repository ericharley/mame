#!/usr/bin/env python3

import os
import select
import sys
import time


device, output = sys.argv[1:3]
fd = os.open(device, os.O_RDWR | os.O_NOCTTY)
deadline = time.monotonic() + 120
data = bytearray()
start = -1

try:
    os.write(fd, b"\x11")  # DC1/XON: printer is ready to receive.
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.25)
        if not readable:
            continue
        chunk = os.read(fd, 4096)
        if not chunk:
            continue
        data.extend(chunk)
        if start < 0:
            start = data.find(b"\x1bP")
        if start >= 0:
            end = data.find(b"\x1b\\", start + 2)
            if end >= 0:
                with open(output, "wb") as stream:
                    stream.write(data[start : end + 2])
                sys.exit(0)
finally:
    os.close(fd)

with open(output, "wb") as stream:
    stream.write(data)
sys.exit(1)
