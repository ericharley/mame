# ROM string reconnaissance

Strings are evidence of content, not address-map evidence.  A conservative
`strings -a -t x -n 8` scan found:

- E1: communications/error text including `response from`,
  `Unable to run with`, `request pending`, and `No response from`.
- E2: terminal control-sequence tables and glyph-like lookup data.
- E3/E4: little plain text, consistent with code and tables.
- E5: setup vocabulary including `RS-232`, `DEC-423`, `monochrome`, `color`,
  refresh rates, baud rates, `XON/XOFF`, and `DEC-MCS`.
- E49: no meaningful prose; its repeated bitmap-like patterns are consistent
  with the schematic's character/video ROM role.

Offsets from a string scan are offsets within each 32 KiB image.  They must
not be treated as CPU addresses until the image's mapping is applied.
