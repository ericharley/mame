# 8031 upper internal-address investigation

## Question

MAME reported repeated CPU2 indirect writes to internal addresses `80-ff`.
The question was whether the board actually uses an 8032-class processor with
256 bytes of internal RAM, despite the schematic's 8031 labels.

## Hardware evidence

- The terminal-control-module schematic labels E24 and E57 `UPROC 8031`.
- The matching parts list calls both devices DEC `21-20115-01`,
  `8031C MICROPROCESSOR W/O P`.
- Intel's 8031AH/8051AH/8032AH/8052AH data sheet distinguishes 128 bytes of
  data RAM in the 8031AH from 256 bytes in the 8032AH.  The 8032 also adds a
  third timer and sixth interrupt source, neither of which appears on the
  VT340 processor sheets.

The physical model is therefore an 8031, not an 8032.

## Initial firmware explanation

The first driver revision incorrectly selected E4 while P3.4 was high.  CPU2
reset begins with `LJMP 0212`; under that wrong selection it called E4 address
`8006`.  The resulting overlapping instruction stream executed:

```text
8006  f0        movx  @dptr,a
8007  04        inc   a
8008  78 04     mov   r0,#04
800a  e0        movx  a,@dptr
800b  f6        mov   @r0,a
800c  08        inc   r0
800d  a3        inc   dptr
800e  d5 f0 f9  djnz  b,800a
```

The reset value of B is zero, so `DJNZ` performed 256 iterations.  R0 crossed
`7f`, producing the upper-IDATA diagnostics.  This looked self-contained but
was not a valid reset routine: it was accidental decoding of E4 bytes from the
wrong bank.

## Controlled comparison

For diagnosis only, both processors were temporarily changed from MAME I8031
to I8032.  With identical ROMs, RAM model, and one-second run:

| Core | Log lines | Timed-stop PC1 | Timed-stop PC2 | Result |
|---|---:|---:|---:|---|
| I8031 | 223,083 | `0991` | `27f5` | Upper-IDATA diagnostics; authentic part |
| I8032 | 3,902 | `2430` | `801a` | Diagnostics hidden; control flow still blocked |

The I8032 substitution did not establish a successful POST.  It also adds
Timer 2 and SFR behavior absent from the documented hardware, so it was
rejected and the driver was restored to I8031.

## Bank-polarity resolution

Selecting E5 while reset P3.4 is high eliminates the CPU2 upper-IDATA flood
and follows coherent code into a DC7051 status poll at `c048-c049`.  Supplying
the documented ready/status bit then advances through explicit board-register
writes and ordinary control flow.  This controlled result supersedes the
initial interpretation of the E4 loop.  See `bank-polarity-investigation.md`.

## Decision

Keep the I8031 devices.  Treat the recorded CPU2 upper-IDATA writes as a
diagnostic artifact of the former wrong-bank implementation, not expected
hardware behavior and not evidence for an 8032.  CPU1's separate stack growth
was localized to a B.0-dependent formatter branch.  A corrected-bank 8052
comparison did not escape that path; the final resolution was the target's
all-ones response for reserved SFR `c2`, not additional internal RAM.  See
`cpu1-stack-investigation.md`.

## Later CPU1 serial-service finding

The decision above remains correct for the original CPU2 wrong-bank symptom
and CPU1 formatter trap, but a later, independent normal-operation trace adds
new evidence.  After POST, CPU1's timer task calls the `bb11` serial poller.
With modeled SCN2681/SCN2641 devices, the poller performs thirteen nested
status passes while the transmitter advances.  SP grows from `58` into the
upper indirect range (approximately `8c`), then unwinds normally to `4d`.

An I8031 core loses the return frames beginning at `80`; an I8032 core follows
the same ROM path to completion, after which CPU1 and CPU2 remain stable at
20- and 30-second checkpoints.  This does not overturn the explicit schematic
and parts-list identification of E57 as an 8031, and the firmware does not use
Timer 2.

The driver has since been returned to I8031. Smoke, Phase 2, Phase 3, and the
current Phase 4 mailbox timeline remain unchanged because the present startup
block occurs before that later serial-service path becomes decisive. The
upper-stack behavior remains an open issue to re-test after the mailbox
ordering problem is resolved; it is no longer hidden by a production CPU
substitution.
