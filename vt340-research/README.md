# DEC VT340 ROM-level emulator research

This directory records the evidence behind the first-stage MAME driver in
`src/mame/dec/vt340.cpp`.  Assertions are classified as confirmed, inferred,
or unresolved.  The original ROM binaries are intentionally kept outside
tracked source under `roms/vt340/`.

Primary evidence:

- DEC drawing set `K-TC-VT340_Schematic_Feb87.pdf`, especially terminal
  control module sheets on scanned PDF pages 18-27.
- Malcolm Macleod's VT340 Internals archive and its buzzed-out cartridge
  wiring table.
- DEC `EK-VT340-PS-002` Pocket Service Guide.
- Intel order 270499-006, the 8031AH/8032AH family data sheet.
- The ROM images themselves.

The exact MAME checkout used for this sprint is commit
`39eb9e44c394df9aec8186f2d2ef7517ace232e1`.

Raw debugger `.tr` streams, diagnostic `.log` files, and framebuffer `.png`
captures are generated evidence and remain local rather than entering Git.
Tracked summaries, disassemblies, and Lua reproduction scripts preserve the
claims and make the bounded experiments repeatable.
