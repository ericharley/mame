# CPU1 formatter-branch and stack investigation

## Symptom

After early shared-RAM initialization, CPU1 repeatedly reports direct reads of
unmapped SFR `c2` and eventually writes stack bytes above the 8031's `7f`
internal-RAM limit.  A debugger execution trace now identifies the exact path.

## Instruction path

The SFR access is an authentic ROM instruction, not a decoded board register:

```text
098b  65 c2     xrl   a,c2
098d  54 30     anl   a,#30
098f  50 06     jnc   0997
...
099e  12 09 e4  lcall 09e4
09e4  30 f0 a3  jnb   b.0,098a
```

When B.0 is clear, the branch deliberately enters at `098a`, one byte before
the normal `098b` entry.  It repeats the formatter path, pushes a separator or
sign byte, and calls `09e4` again.  The first observed failing call has SP=`0c`,
A=`2f`, B=`00`, and DPTR=`5f45`; subsequent iterations add three stack bytes.
This explains both the C2 diagnostic and later stack growth.  A fresh trace
also established that MAME's unmapped-SFR fallback returned `00`: A entered
`098b` as `2f` and became `20` after `XRL A,C2` and `ANL A,#30`.

The apparent earlier upper-IDATA read was reclassified after disassembling the
overlapping entry at `2742`.  `MOV A,@R1` executes as an entry side effect, but
`MOVX A,@DPTR` at `2746` immediately replaces A before it is used.  Calls use
R1 values including `80` and `c0`, but the upper-IDATA value is discarded; it
is not evidence for a 256-byte processor.

## Controlled core comparison

The comparison was repeated with the then-current CPU2 bank model and the
then-unidentified register window (subsequently established as the DC323):

| CPU1 core | One-second log lines | Upper-IDATA diagnostics | C2 reads | Result |
|---|---:|---:|---:|---|
| I8031 | 160,017 | 95,901 | 63,964 | Authentic core; recursive bad path |
| I8032 diagnostic substitute | 64,122 | 0 | 63,964 | Extra RAM hides stack warnings; same bad path and stop PC |

The I8032 substitution changes storage capacity but not the failing control
flow: both variants stop at CPU1 `099e` after one second.  It is therefore not
a fix and was removed.

## Decision

Keep the documented I8031 and install a CPU1-only read response of `ff` for
reserved SFR `c2`.  This is the smallest behavior that matches the ROM's
intent: the formatter loop disappears, the one-second diagnostic log falls
from 160,017 lines to roughly 1,400 before extra mailbox tracing, and CPU1
advances from `099e` to `9079`.

At `906a-907b`, CPU1 writes `ff` to shared RAM `7ff1` and waits for CPU2 to
replace it.  CPU2 ROM has matching clears at E3 `0f27` and `0f3c`, but it never
accesses `7ff1` after CPU1 posts the request.  The CPU1 stack/SFR failure is
therefore resolved; the current blocker is CPU2's earlier graphics startup.
