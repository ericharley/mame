# VT340 integration-test fixtures

`bill-the-cat.six` is a 16-entry-palette, 330 by 440 SIXEL rendition used to
exercise the VT340 firmware's native SIXEL parser and graphics-command path.
The color acceptance test sends the original fixture through a raw Comm 1
pseudo-terminal and compares every CPU-visible receive byte with it.
