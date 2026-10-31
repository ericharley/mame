# First-stage hardware block diagram

```text
          E1 0000-7fff    E2 8000-ffff
                 \        /
                  E57 8031 (processor 1)
                    ^    \
      external T1   |     +-- E93/E94 shared 64 KiB RAM --+
                    |    /                                 |
        P1.1 DAT9/STATUS H                                 |
                  E24 8031 (processor 2) <--- DC323 INT L  |
                 /        \                                |
          E3 0000-7fff    E4/E5 banked 8000-ffff           |
                    |        |                             |
        DC7051 status   P3.4 / T0 bank latch               |
             register 3                                    |
                                                           |
          E49 27256 character/video ROM --> video circuitry
```

Both processors receive clocks derived from the board's 12 MHz oscillator.
This diagram intentionally omits unimplemented serial, EEPROM, most latches,
and the rest of the video path; those are tracked in `unknowns.md`.
