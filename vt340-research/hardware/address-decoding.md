# Program address decoding

The ROM-cartridge connector J5 and the physically buzzed-out cartridge table
agree on every program address, data, output-enable, and chip-enable signal.

- E1 `/CE` <- AA15 H; E2 `/CE` <- AA15 L.
- E3 `/CE` <- BA15 H.
- E4 `/CE` <- B0SEL L; E5 `/CE` <- B1SEL L.
- `B0SEL_L = BA15_L OR ROMBANK0_L`.
- `B1SEL_L = BA15_L OR ROMBANK1_L`.
- ROMBANK1 L is processor 2 INT1/P3.3.

The active-level notation across the cartridge and PAL sheets is easy to
misread in isolation.  A controlled firmware comparison resolves the dumped
five-ROM cartridge's effective polarity: P3.3 high selects E4; P3.3 low
selects E5.  The resulting execution completes POST and enters the coherent
E4 normal-operation loop.  The first hardware poll is in the DC323 block.

The five-ROM cartridge uses two independent buses exactly as observed during
dumping.  No guessed concatenation is used in the ROM declarations.
