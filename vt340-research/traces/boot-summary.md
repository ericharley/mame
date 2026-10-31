# Deterministic first boot checkpoint

Build with `VERBOSE` temporarily set to `LOG_PORTS | LOG_XDATA`, then run:

```sh
./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1 -log
```

Observed with MAME commit `39eb9e44c394df9aec8186f2d2ef7517ace232e1`:

```text
VT340 reset: CPU1 E1/E2, CPU2 E3/E5 selected
CPU1 XDATA W 0000=90 (PC=0201)
CPU1 XDATA W ECC8=F0 (PC=0037)
CPU1 XDATA W 4C72=86 (PC=7479)
CPU2 XDATA R FF03 (PC=C049)
CPU2 P1 FF -> 1F (PC=C04F)
CPU2 XDATA W FF2A=FF (PC=C054)
CPU2 P1 1F -> 00 (PC=C05A)
CPU2 XDATA W FF2B=00 (PC=C061)
CPU2 XDATA W F020=00 (PC=029A)
CPU2 XDATA W F021=00 (PC=029D)
CPU2 XDATA W F021=FF (PC=1805)
CPU1 XDATA W 7FF1=FF (PC=9070)
CPU1 XDATA R 7FF1 (PC=907A)
VT340 stop: CPU1 PC=9079 CPU2 PC=E6E0 CPU2 IE=00 TCON=00 bank=1
```

The CPU2 writes are 16-bit DC7051 values.  Combining CPU2 P1 with the logged
MOVX byte yields register 2a=`1fff`, 2b=`0000`, 20=`0000`, and register 21
changing from `0000` to `00ff`.

The raw log is intentionally not versioned.  Selecting E5 on reset removes
the former 220,000-line CPU2 upper-IDATA flood and reaches the real DC7051
poll.  The driver's XDATA logging is capped separately for general and `fxxx`
I/O-page accesses.  CPU1's direct SFR `c2` read and later stack growth are now
resolved by returning the target's all-ones value for that reserved location.
CPU1 now posts `ff` to shared mailbox byte `7ff1` and waits for CPU2 to clear
it.  CPU2 remains in graphics initialization with interrupts disabled and does
not yet service that mailbox.  The checkpoint proves reset-vector, corrected
ROM-bank, shared-RAM, and first peripheral-status execution; it does not prove
successful POST.
