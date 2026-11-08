# VTTEST 11.2.2 versus VT340 panning

## Result

The diagonal stars produced by VTTEST 11.2.2 are not evidence that the VT340
firmware dropped `SU` (`CSI Pn S`) or `SD` (`CSI Pn T`).  This test reuses
VTTEST's generic ECMA-48 scroll-up and scroll-down routines, whose expected
result assumes that character data moves in page memory.

The VT340 assigns these sequences to **Pan Down** and **Pan Up**.  Panning moves
the 24-line user window over unchanged page memory.  Characters written on a
diagonal therefore remain on a diagonal.  DEC explicitly warns that the ANSI
mnemonics are only references and do not describe VT300-series behavior.

The default VT340 page is 24 lines high, exactly the height of the user window.
In that format neither command can move the window.  A larger page can be
selected with DECSLPP, for example `CSI 72 t`.

References:

- `references/library/EK-VT3XX-TP-002_VT330_VT340_Text_Programming_May88.pdf`,
  pages 107 and 159–165.
- VTTEST `vt320.c`: `tst_vt320_cursor` labels the generic `tst_SU` and `tst_SD`
  functions as Pan Down and Pan Up.
- VTTEST `nonvt100.c`: those generic functions say they force a diagonal into
  a horizontal row using scroll semantics.

## Emulator evidence

The original 24-line reproduction delivered every byte and all 20 CPU1 ring
packets.  CPU2 consumed all 20 opcode-`38` packets and entered the native pan
handler at `DC95`.  Because the page and user window were both 24 lines high,
the handler correctly scheduled no DC323 operation.

A controlled 72-line page test demonstrated native Pan Down:

1. Select a 72-line page with `CSI 72 t`.
2. Reset vertical cursor coupling with `CSI ? 61 l` so off-screen writes do not
   move the window implicitly.
3. Write labeled rows 1 through 25.
4. Send `CSI S`.

The display changed from rows 1–24 to rows 2–25, and the DC323 received a
20-scanline upward scroll operation.  This proves that the command path and
page-window movement work.

The focused byte-stream generator is `fixtures/vttest-pan.sh`:

```sh
sh vt340-research/fixtures/vttest-pan.sh pan-down
sh vt340-research/fixtures/vttest-pan.sh pan-up
sh vt340-research/fixtures/vttest-pan.sh vttest-su
sh vt340-research/fixtures/vttest-pan.sh vttest-sd
```

The first two modes test VT340 panning semantics.  The last two reproduce the
generic VTTEST star patterns without its menus.

## Remaining separate defect

The controlled Pan Up run first pans down one line, then pans back up.  The
window returns to rows 1–24, but parts of the left side of some restored rows
are damaged.  The firmware issues the reverse 20-scanline DC323 operation, so
this is a distinct down-scroll/backing-store restoration defect.  It does not
cause VTTEST's diagonal result on the default 24-line page and should be fixed
and regression-tested separately.
