# ReGIS grid and RAF raster trace

## Symptom

The unmodified `vt340test/regis/registest.sh` stream drew only the horizontal
parts of the grid. ReGIS text was absent, and the RAF roundel produced no
visible circles. The PTY delivered the complete streams; its normal LF-to-CRLF
output processing was accepted by the terminal firmware and was not causal.

## Firmware-generated operations

The RAF test produced 907 normal-mode `06c0` constant-source raster commands.
The firmware represented each filled circle as a series of one-pixel-wide
vertical spans. A representative command used destination origin `(342,200)`,
fast vector `(0,-83)`, slow vector `(0,1)`, and mode `00c0`.

The grid test used three relevant forms:

- axis-aligned `06c0` commands for horizontal grid lines;
- rotated normal and linear-pattern destination vectors for vertical lines;
- `0ec0` glyph copies and `06c0` backing operations in mode `00d0` for ReGIS
  text, including rotated labels.

Mode `00d0` is normal mode with pen down, destination indexing, and hole-fill
enabled. DC323 mode selection is encoded only in bits 0-1; bit 4 does not
select a separate raster mode.

## Root causes and correction

The extracted DC323 had two independent rejection paths:

1. It classified normal mode by requiring mode bits 0-4 to be zero. That
   incorrectly rejected every `00d0` text operation.
2. It returned without drawing whenever fast-DY or slow-DX was nonzero. That
   discarded rotated text, vertical grid lines, and every RAF circle span.

The corrected normal and linear-pattern engines walk both signed destination
vectors. Each vector uses the Dragon specification's Bresenham initialization:
the error starts at minus the major-axis magnitude, the origin is selected,
and the endpoint at `origin + delta` is excluded. Fast and slow paths combine
to form the destination parallelogram while source scaling and Viper Boolean
operations retain their existing roles.

No ReGIS parser, firmware address, command-specific shape, or expected bitmap
was added to the emulator.

## Verification

- The firmware-free DC323 regression covers mode bit 4, a rotated rectangle,
  the documented 4-by-2 Bresenham path, and a rotated linear-pattern raster.
- All 907 RAF `06c0` spans execute and produce the three concentric circles.
- The native color configuration produces the expected blue, white, and red
  RAF roundel.
- The grid produces both axes and all horizontal and rotated text labels.
- Existing native graphics, Set-Up return, and startup regressions remain the
  required broader checks.

Remaining vector fidelity work includes programmable Bresenham error offsets
and exact hole filling for oblique parallelograms.
