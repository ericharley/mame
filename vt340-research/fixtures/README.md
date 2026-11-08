# VT340 integration-test fixtures

These are stable, tracked test inputs. Runnable tests reference them from
`../tests/manifest.json`; generated logs, JSON events, screenshots, and hashes
belong in the ignored `../test-results/` tree created by `../tests/run.py`.

`bill-the-cat.six` is a 16-entry-palette, 330 by 440 SIXEL rendition used to
exercise the VT340 firmware's native SIXEL parser and graphics-command path.
The color acceptance test sends the original fixture through a raw Comm 1
pseudo-terminal and compares every CPU-visible receive byte with it.

`bill-the-cat-8color.six` is the visually optimized interactive variant. It
uses the same dimensions and run-length encoder, but quantizing to eight colors
reduces the stream from 93,198 to 55,560 bytes (40.4 percent). At 9600 baud,
that reduces ideal wire time from about 97 seconds to 58 seconds. The original
16-color fixture remains the regression input because it exercises every
framebuffer plane combination.

The optimized variant was generated with:

```sh
python vt340-research/tools/png_to_sixel.py bill_16colors.png \
    --width 330 --colors 8 -o bill-the-cat-8color.six
```

`fast-start.cfg` is an isolated MAME configuration used by
`tests/fast-start.sh`. It selects the optional CPU1 checkpoint ROM patch
without changing the developer's normal `cfg/vt340.cfg` or the default
research behavior.

`regis-hex-patterns.regis` is a generated ReGIS conformance stream containing
six honeycomb panels: diagonal stripes, checkerboard, dots, crosshatch,
chevrons, and a small bitmap-like diamond motif. Patterns use global screen
coordinates and are clipped independently to every hexagon, so adjacent cells
expose discontinuities in vector clipping or polygon composition. Regenerate
it deterministically with:

```sh
python3 vt340-research/tools/generate_regis_hex_patterns.py \
    vt340-research/fixtures/regis-hex-patterns.regis
```

`regis-hex-linear-patterns.regis` uses the same continuous honeycomb, but its
interior strokes select six combinations of ReGIS binary writing patterns and
pattern multipliers with `W(P...M...)`. This is the focused firmware-level
exercise of DC323 linear-pattern mode. Regenerate it with:

```sh
python3 vt340-research/tools/generate_regis_hex_patterns.py \
    --linear-patterns vt340-research/fixtures/regis-hex-linear-patterns.regis
```
