# VTTEST 11.2.3 page-format tests on the VT340

## Result

VTTEST 11.2.3 relies on the DEC screen-alignment pattern (`DECALN`, `ESC # 8`)
to fill the screen with `E` characters before changing the page dimensions.
The native VT340 firmware used by this emulator ignores that sequence in its
normal VT300 operating mode.  Consequently, the large field of `E` characters
that VTTEST tells the user to inspect is blank.

This is independent of DECSCPP and DECSLPP.  Both page-format sequences reach
the native firmware, and text written after them is displayed normally.
DECSLPP with a 72-line page was also verified independently by panning the
24-line user window from page rows 1–24 to rows 2–25.

## Evidence

The focused fixture sent these two streams in separate cold boots:

1. `CSI ? 25 l`, `CSI 2 J`
2. `CSI ? 25 l`, `CSI 2 J`, `ESC # 8`

All serial bytes arrived without error.  The two runs produced identical:

- CPU1-to-CPU2 packet streams after the clear operation;
- final framebuffer hash `1465AB2B`;
- blank main display with the normal status line.

Adding ordinary `E` characters after the clear displayed them correctly, so
the result is not a character-rendering or serial-input failure.  Adding text
at row 20 after either `CSI 80 $ |` (DECSCPP) or `CSI 36 t` (DECSLPP) also
displayed correctly.

The VT330/VT340 Text Programming manual documents the page-format controls but
does not list DECALN among the terminal's text control functions.  It permits:

- single session: 24, 36, 72, or 144 lines per page;
- dual session: 24, 36, or 72 lines per page;
- 80 or 132 columns per page.

VTTEST tries line counts 24, 25, 36, 48, 72, and 144.  The 25- and 48-line
requests are not VT340 page formats and should leave the current format
unchanged.

## What VTTEST is doing

For each case, VTTEST performs this sequence:

1. Erase the display.
2. Send DECALN to create the field of `E` characters.
3. Send DECSCPP or DECSLPP.
4. Draw a ruler and explanatory message near the bottom of the display.
5. Wait for Return before continuing to the next format.

On this VT340, step 2 has no effect.  The ruler/message from step 4 should
still appear.  A blank field above that message does not indicate a failed
page-format command.  If the ruler and message are also absent, that is a
separate reproduction and should be captured before pressing Return.

## Reproducer

`fixtures/vttest-page-format.sh` provides isolated streams for the alignment
pattern and each supported page-format command.  For example:

```sh
sh vt340-research/fixtures/vttest-page-format.sh align
sh vt340-research/fixtures/vttest-page-format.sh columns-80-message
sh vt340-research/fixtures/vttest-page-format.sh lines-36-message
```

The fixture deliberately separates DECALN from post-format text so the two
behaviors cannot be confused.
