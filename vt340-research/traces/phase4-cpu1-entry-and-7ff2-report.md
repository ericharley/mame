# CPU1 LK201-entry trace and complete `7ff2` protocol

## Conclusions

1. The final `11 8f 13 8c` LK201 command block is unconditional once CPU1
   successfully accepts response 5.  There is no branch, device read, UART
   status test, or keyboard-response test between the successful return from
   the first `3b9a` exchange and the second `LCALL 3b9a`.
2. Response 5 is accepted from a genuine physical DAT9 event.  CPU2 drives
   P1.1 low while issuing the first DC323 zero command at `bb91-bb98`, and
   later drives it high with the first direct-register high byte.  CPU1 polls
   the directly connected P3.5/T1 pin and sees those levels.  No retained
   pulse or PC-qualified status substitution supplies this response.
3. Static and dynamic cross-references prove that the post-test `7ff2` **fast
   path** is sentinel `10` -> checkpoint `00` -> terminal nonzero result.  This
   is no longer an inference from the failing trace.  CPU1 writes `10`
   specifically to invalidate the stale zero left by destructive RAM testing,
   waits preferentially for a new zero, and then waits for a nonzero final
   result.  CPU2 never reads the sentinel.
4. The complete protocol also has a bounded checkpoint-timeout fallback.  In
   an unmodified 160-second cold run, CPU1's first loop expired with the
   authentic `80` still present, the second loop accepted it immediately, and
   CPU1 reached native success path `4551` at 119.995547 s.  The inversion
   therefore causes roughly 112 seconds of avoidable delay, not permanent
   deadlock.

No timing or hardware behavior was changed.

## Reproducible trace

`phase4-cpu1-lk201-entry.lua` activates at CPU1 `39d3`, after the earlier POST,
and stops immediately before the `3a0d` sentinel write.  It records only the
RAM-test decision boundaries, final exchange calls, four SBUF writes, DAT9
sampling loops, and relevant CPU/port state.  It does not write emulator state.

The separate `phase4-mailbox-lifecycle.lua` tap records every dynamic access
to physical shared address `7ff2`, including the indirect destructive RAM
tests that do not have a literal `MOV DPTR,#7ff2` cross-reference.

## Backward control-flow trace

### Immediate predecessor graph

```text
39d3  R0=aa
       |
       v
3a59  shared-RAM test over 0000-efff
       | carry clear on every readback comparison
       v
39d8  JC 39e7                 failure only
39da  rotate pattern aa -> 55
39dd  JB ACC.0,39d5           repeat with 55
       |
       v
39e0  R0=00
3a59  verify prior 55, clear shared RAM to 00
39e5  JNC 39ea                observed taken
       |
       v
39ea  R3=0a
39ec  LCALL 3b9a              block 11 8f 13 8b, pulse 5, wait response 5
       |
       | successful response returns at 3bce
       v
39ef  LCALL 3b9a              no intervening branch
       |
       v
3ac9  block 11 8f 13 8c, pulse 6, wait response 6
       |
       v
39f2  unrelated B.0 option
39fb  compute E795 from released P1.7/P1.6 outputs
3a08  DPTR=7ff2
3a0d  write sentinel 10
```

### Observed decision timeline

| Time (s) | PC | State | Decision |
|---:|---:|---|---|
| 4.719863 | `39d3` | `R0=aa` | enter final shared-RAM tests |
| 5.768773 | `39d8` | carry clear | AA pass; do not take failure branch |
| 5.768778 | `39dd` | rotated `A=55`, bit 0 set | repeat test with `55` |
| 6.817738 | `39d8` | carry clear | 55 pass; do not take failure branch |
| 6.817743 | `39dd` | rotated `A=aa`, bit 0 clear | leave pattern loop |
| 6.817745 | `39e0` | `R0=00` | enter verify-55-and-clear pass |
| 8.206937 | `39e5` | carry clear | take success path to `39ea` |
| 8.206940 | `39ec` | `R3=0a` | call exchange 1 |
| 8.222100 | `3bc8` | DAT9 high after low | accept response 5 |
| 8.222106 | `3bce` | saved registers restored | return from exchange 1 |
| 8.222108 | `39ef` | no state test | call exchange 2 unconditionally |
| 8.222112 | `3ac9` | `R3=0b` | increment to `0c`, construct second block |
| 8.295748 | `3bc8` | DAT9 high after low | accept response 6 |
| 8.295771 | `3a0d` | `A=10`, `E795=01` | write sentinel `7ff2=10` |

### Hardware-derived conditions and provenance

| Condition | Firmware use | Physical/emulated source | Observed value | Effect on entry |
|---|---|---|---|---|
| Shared-RAM readback | `3a7a-3a93`, carry returned to `3a64`, `39d8`, and `39e5` | E93/E94 shared SRAM through CPU1 external bus | AA, 55, and 00 comparisons pass; carry clear | only immediate success/failure decision before final exchanges |
| DAT9 low | `3bab JNB T1` | resolved `P2 DAT9/TSTATUS H`; CPU2 P1.1 is low | low sampled during CPU2 DC323 zero command | completes first half of response 5 |
| DAT9 high | `3bbc JB T1` | same net; CPU2 P1 high byte becomes `3f` | high sampled during first direct-register record | completes response 5 and permits return |
| Timer 0 interrupts | interrupt vector `000b` during software pacing | CPU1 board timer configuration | seven services occur between response 5 and pulse 6 | preempt and return; do not select or terminate the block |
| UART transmit state | `3b64` | CPU1 internal UART/LK201 TX line | firmware clears TI and writes SBUF | output only; TI is never polled by this routine |
| Keyboard RX/acknowledgement | none in `3ac9-3b77` | LK201 serial receive path | not read | cannot condition the block |
| `B.0` | `39f2 JNB B.0` after both exchanges | B was initialized earlier to the board/startup option byte; observed `B=40` | zero | skips optional `7ff4` copy; occurs after the block |
| P1.7 / P1.6 | reconstructed `39ff-3a07`, after both exchanges | CPU1 output nets `NVRCLK H` and `CPMRESET H` | both released high in `P1=dc` | computes `E795=01`; cannot condition entry into the block |

The page-final byte at logical `39ff` is another place where the unreconstructed
linear disassembly is misleading.  The reconstructed instruction is
`30 97 05` (`JNB P1.7,3a07`), not `70 97` (`JNZ 3998`).  The executed logic is:

```text
A = 0
if P1.7 is high: A = 1
if P1.7 is high and P1.6 is low: A = 2
write A to E795
```

Observed P1=`dc` has both bits high, hence `E795=01`.  Both schematic names are
firmware-driven outputs, not external configuration straps.

## The four-byte block is unconditional

`3ac9` increments R3, saves DPTR, sets `R4=3`, and reads the three fixed ROM
bytes at `3afa`: `11 8f 13`.  It calls `3b64` once for each fixed byte, then
sets bit 7 of R3 and calls `3b64` for the fourth byte.  `3b64` performs:

```text
CLR  TI
MOV  SBUF,A
three fixed software-delay passes
RET
```

There is no input-dependent branch in that sequence.  The trace records:

| Exchange | Entry | Bytes | Pulse | Following wait |
|---:|---:|---|---:|---|
| 1 | 8.206944 | `11 8f 13 8b` | 8.220511 | response 5 |
| 2 | 8.222112 | `11 8f 13 8c` | 8.235679 | response 6 |

The only failure alternative is inside the preceding response wait: if DAT9
does not reach low and then high before the nested timeout counters expire,
firmware jumps to the fatal path at `3933`.  Once `3bce` returns normally,
`39ef LCALL 3b9a` is the next instruction.

## Response 5 physical-source proof

CPU1 enters its low wait at 8.220540 s.  CPU2 has just left its sixth `1701`
rendezvous and is executing the zero-configuration and first `17cf` group.

| Time (s) | CPU1 observation | CPU2 state/source | Physical DAT9 |
|---:|---|---|---|
| 8.220540 | first `3bab` low-wait sample | CPU2 `2f51`, P1=`02` | high |
| 8.221939 | — | `bb93` writes CPU2 P1=`00` for the DC323 zero command | falling edge |
| 8.221952 | `3bab`, after 277 samples | CPU2 `bb61`, P1=`00` | low accepted |
| 8.222091 | — | direct table loads P1=`3f` | rising edge |
| 8.222098 | `3bbc`, after 36 samples | CPU2 `bb6d`, P1=`3f` | high accepted |
| 8.222100 | `3bc8` | — | response complete |

This event is graphics-bus activity, not a dedicated second `1701` pulse.  It
is nevertheless the intended *qualifying physical event* for the executed
firmware contract: CPU1 deliberately polls the unqualified shared DAT9 level,
CPU2 is the legitimate bus owner, and this is the first complete low/high
level sequence after pulse 5.  The circuit provides no source tag that would
allow CPU1 to distinguish a handshake value from graphics data.

The compatibility paths in `cpu2_p1_r()` affect CPU2's own selected status
reads.  CPU1 is polling through `cpu1_p3_r()` at `3bab/3bbc`; the retained
CPU2 pulse is only consumed at CPU1 PC `3925`.  Neither accommodation applies
here.

## Complete `7ff2` access inventory

### Static explicit cross-references

Searching all five cartridge ROM images finds three literal CPU1 references,
five literal CPU2 references, and none in E2, E4, or E5.

| CPU | PC | Operation/meaning |
|---|---:|---|
| CPU1 | `3a08` | establish DPTR, then `3a0d` writes sentinel `10` |
| CPU1 | `3a2a` | re-establish DPTR for terminal-result wait at `3a31` |
| CPU1 | `3aaf` | error reporter reads result at `3ab2` and `3abc` |
| CPU2 | `1369` | `136d` writes normal checkpoint `00` |
| CPU2 | `159a` | `159f` writes error accumulator `$74`, then stops |
| CPU2 | `1639` | `163e` writes success `80` |
| CPU2 | `1975` | `197a` writes computed `$74` error, then stops |
| CPU2 | `1b1d` | `1b24` writes `$74+B` error, then stops |

CPU2 has no explicit or observed protocol-phase read of `7ff2`.

### Dynamic indirect accesses before the protocol

Address `7ff2` is ordinary shared RAM during destructive POST, so generic
MOVX loops access it without a literal address reference:

| Time (s) | CPU/PC | Access | Phase |
|---:|---|---|---|
| 2.476537–2.476539 | CPU2 `badb/badc` | write/read `aa` | CPU2 RAM pattern test |
| 3.263508–3.263510 | CPU2 `badb/badc` | write/read `55` | CPU2 RAM pattern test |
| 4.181493–4.181501 | CPU2 `baf0/baf6/baf7` | verify `55`, write/read `00` | CPU2 RAM clear |
| 5.291844–5.291846 | CPU1 `3a89/3a8a` | write/read `aa` | CPU1 RAM pattern test |
| 6.340752–6.340754 | CPU1 `3a89/3a8a` | write/read `55` | CPU1 RAM pattern test |
| 7.570968–7.570976 | CPU1 `3a83/3a89/3a8a` | verify `55`, write/read `00` | CPU1 RAM clear |

The last operation leaves a stale baseline zero before either processor uses
the address as a result-state byte.

### Protocol state machine proved from readers and writers

```text
destructive RAM tests leave 00
              |
              v
CPU1 writes 10 after final DAT9 response
  (invalidates the stale baseline; CPU2 does not read it)
              |
              v
CPU1 3a18 waits preferentially for 00
  - new 00 means CPU2 reached checkpoint 136d
  - persistent nonzero eventually times out, allowing an early error result
              |
              v
CPU1 performs inter-stage work and sends another LK201 block
              |
              v
CPU1 3a31 waits for nonzero terminal result
              |
       +------+------+
       |             |
      80          other nonzero
    success       CPU2 error code
       |             |
     4551       3aaf error reporter
```

The first loop is bounded by three nested 8-bit counters.  It exits
immediately on zero, but it can also expire with a persistent nonzero CPU2
error or success value so that the second-stage logic can classify that value.
The second loop similarly prefers a nonzero terminal result.  Thus zero is an
intermediate fast-path checkpoint, not a final success value, and `10` is a
stale-zero guard rather than a CPU2 request.

The normal fast-path ordering `10 -> 00 -> 80` is established by instruction
semantics and the complete writer set, not assumed from the prior successful
timing experiment.  It is not an absolute prerequisite for eventual success:
the bounded first-stage timeout permits `10 -> 80` to reach classification.
CPU2's error paths replace terminal `80` with values based on `$74`; they do
not add another normal checkpoint writer.

## Observed slow fallback under that protocol

| Time (s) | Access | Consequence |
|---:|---|---|
| 8.228779 | CPU2 `136d` writes `00` | sole normal checkpoint is published while CPU1 is in the second LK201 block |
| 8.295771 | CPU1 `3a0d` writes `10` | stale-zero guard overwrites the already-published checkpoint |
| 8.309671–13.194725 | CPU1 `3a18` reads `10` 734,084 times | first-stage loop cannot observe a new zero |
| 13.194725 | CPU2 `163e` writes `80` | authentic success arrives |
| 13.194725–119.955290 | CPU1 `3a18` reads `80` | remains in the bounded checkpoint loop |
| 119.955290 | CPU1 reaches `3a21` with `A=80` | checkpoint wait expires after approximately 111.646 s |
| 119.995537 | CPU1 reaches `3a31` | terminal-result loop reads the retained `80` immediately |
| 119.995547 | CPU1 reaches `4551` | authentic native success path |

The second LK201 block and response-5 acceptance are both legitimate.  They
do not explain why CPU2's checkpoint precedes the sentinel; they make the
firmware-level timing mismatch more precise.  The mismatch loses the fast
checkpoint but does not lose the terminal result.

## Next investigation boundary

The CPU1 branch has no remaining input that can lawfully remove the delay, and
the bounded CPU2 audit found no missing successful-path wait.  Further timing
changes need new external evidence—a real-hardware startup capture, service
documentation, or independently sourced firmware behavior.  The current
firmware does eventually enter success on its designed timeout fallback, so
no mailbox or delay workaround is justified by this investigation.

