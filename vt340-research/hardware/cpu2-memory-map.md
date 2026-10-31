# Processor 2 memory map (E24)

## Program space

| Range | Device | Status |
|---:|---|---|
| `0000-7fff` | cartridge E3 | Confirmed |
| `8000-ffff` | cartridge E4 or E5 | Confirmed; P3.3 high selects E4, low selects E5 |

J5 routes BA0-BA14, BAD0-BAD7, and BPSEN L to E3/E4/E5.  E3 `/CE` is BA15
H.  E4 and E5 `/CE` use B0SEL L and B1SEL L respectively.  Schematic page 20
shows the select equations and identifies INT1/P3.3 as ROMBANK1 L.  Controlled
boot traces resolve the effective polarity: reset-high selects E4 and reaches
coherent initialization; the firmware selects E5 when required.

## External data space

| Range | Device | Status |
|---:|---|---|
| `0000-ffff` | shared E93/E94 RAM | Confirmed physical RAM backing |
| `f?00-f?3f` | E70 DC323 Adder 16-bit registers | Confirmed overlay; BA11-BA8 mirrored |

Shared byte `7ff1` is the first confirmed CPU1-to-CPU2 completion mailbox.
CPU1 posts `ff` and waits for CPU2 to change it; CPU2 E3 code clears it at
`0f27` and `0f3c`.  The current driver completes POST, enters the E4 normal
loop, and executes the first normal text rasterops.

The E15 PAL selects the first 64 DC323 registers in the `f000` I/O page;
BA11-BA8 are not decoded by this first model, so the block mirrors from
`f000-f03f` through `ff00-ff3f`.  CPU2 P1 supplies data bits 15-8 while MOVX
supplies bits 7-0.  Register 3 exposes the firmware-required ready conditions.
The retained register file now drives the proven E49 text rasterop path.  See
`video-hardware.md` for identified register names and `cpu1-memory-map.md` for
the page-21 RAM and bus-multiplexing evidence.

E70 DC323's active-low interrupt output drives CPU2 INT0 as `P10 INTRREQ L`.
The interrupt line is confirmed schematically.  The driver currently asserts
its frame event from the programmed 526-line timing model.
