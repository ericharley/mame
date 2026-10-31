# CPU2 upper-ROM bank-polarity investigation

> Superseded investigation: this early comparison attributed the bank signal
> to P3.4 and consequently reversed E4/E5.  Schematic rechecking and coherent
> full-POST execution establish P3.3 high = E4 and P3.3 low = E5 in the
> current driver.  Retained here as a record of the discarded hypothesis.

## Problem

The first driver treated reset P3.4 high as E4 selected.  CPU2 then entered
E4 at `8006`, produced extensive upper-IDATA diagnostics, corrupted its stack,
and never reached recognizable board initialization.  The schematic equations
establish the two bank selects but their active-level naming did not by itself
settle the cartridge's effective polarity.

## Controlled comparison

Only the P3.4-to-bank mapping was changed between the first two runs:

| Reset selection | Result after one second |
|---|---|
| E4 | Overlapping stream at `8006`; more than 220,000 log lines; CPU2 stop `27f5` |
| E5 | Coherent calls into E5; stable poll of XDATA `ff03` at `c048-c049` |

The E5 path around the first hardware dependency is:

```text
c043  mov   r0,#03
c045  mov   p1,#ff
c048  movx  a,@r0
c049  jnb   acc.4,c048
c04c  mov   p1,#1f
c04f  mov   a,#ff
c051  mov   r0,#2a
c053  movx  @r0,a
...
c05e  mov   r0,#2b
c060  movx  @r0,a
c061  ret
```

With P2 supplying the high address byte, the first `MOVX` reads `ff03`.
Schematic decoding identifies this as mirrored DC7051 register 3.  A minimal
bit-4 status response advances the path to 16-bit DC7051 writes at registers
2a, 2b, 20, and 21; the one-second stop is CPU2 `e6e0`, still in E5 bank 1.

## Decision

Reset P3.4 high selects E5; low selects E4.  The earlier E4 loop and its
upper-IDATA writes were artifacts of the reversed driver polarity.  The E5
execution trace provides stronger validation than interpreting signal names
without the complete cartridge strap context.
