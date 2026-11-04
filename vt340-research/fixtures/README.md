# VT340 integration-test fixtures

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
