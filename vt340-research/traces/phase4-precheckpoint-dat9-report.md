# CPU2 pre-checkpoint timing and DAT9 ownership

## Result

**Outcome D — no qualifying mechanism found.**

CPU2's executed path from `1325` through the `136d` checkpoint is deterministic
under the observed `e795=00` configuration.  The checkpoint write begins 8,268
8031 machine cycles after entry and is complete at cycle 8,270.  At 12 MHz one
classic 8031 machine cycle is one microsecond.

The path contains no interrupt, DC323 ready poll, DC323 completion poll, frame
wait, or variable command-latency mechanism.  Its only live timing input is
CPU2 T0 (`P10 HSYNC H`), first used to align to a horizontal-timing edge and
then counted during a fixed firmware loop.  In the successful observed path
the alignment costs 20 cycles and the final count is the required `0061`.
Changing its phase can move execution by at most approximately one horizontal
period, not the required 6.9 ms; an incorrect count traps the firmware instead
of selecting a longer successful path.

The schematic also establishes that CPU2 P1.1, CPU1 P3.5/T1, and DC323 DAT9
are directly connected on `P2 DAT9/TSTATUS H`.  CPU2 graphics-table writes can
therefore create legitimate transitions visible to CPU1.  The current MAME
model has PC-qualified DC323 status substitutions that should eventually be
replaced with bus-cycle ownership, but those substitutions do not generate the
response-6 edge and cannot reverse the mailbox ordering.

No production correction was made.

## Method

`phase4-precheckpoint-path.lua` enables breakpoints and XDATA taps only from
CPU2 `1325` until the instruction following `136d`.  It records time as integer
1 MHz MAME ticks.  Breakpoints at interrupt vectors `0003` and `000b` verify
interrupt entry without unrestricted instruction logging.  A clean cold boot
produced 284 compact records and terminated at CPU2 `136e`.

The absolute run used the established configuration-entry time of
8.220511 s.  Add the relative cycle count in this report as microseconds to
correlate an event with the cross-CPU trace.

## CPU2 execution report

### Routine-level timing

The table distinguishes an instruction's observed entry coordinate from the
coordinate after its caller regains control.  Consequently the first `17cf`
body spans 2,383–2,384 cycles depending on whether the caller's return/call
boundary is included.

| Routine / phase | Entry PC | Exit coordinate | Calls | Total cycles | Elapsed |
|---|---:|---:|---:|---:|---:|
| Read `e795`, choose zero path | `1325` | `30f9` at cycle 10 | 1 | 10 | 10 us |
| Zero configuration and two DC7051 table copies | `30f9` | caller `1332` at 372 | 1 | 362 | 362 us |
| Call/branch boundary | `1332` | first `17cf` at 376 | 1 | 4 | 4 us |
| First DC323 group including caller boundary | `17cf` | second `17cf` at 2,761 | 1 | 2,385 | 2.385 ms |
| Second DC323 group | `17cf` | timer setup `1340` at 5,144 | 1 | 2,383 | 2.383 ms |
| Timer setup and T0 edge alignment | `1340` | loop `135a` at 5,174 | 1 | 30 | 30 us |
| Fixed `r1=06`, `r0=00` loop | `135a` | timer stop `135e` at 8,258 | 1 | 3,084 | 3.084 ms |
| Timer validation and checkpoint write | `135e` | after write, `136e` at 8,270 | 1 | 12 | 12 us |
| **Complete bounded interval** | **`1325`** | **`136e`** | **1** | **8,270** | **8.270 ms** |

The `136d MOVX @DPTR,A` instruction is entered at cycle 8,268.  This reconciles
the earlier coarse interval report of 8.268 ms to the write's start; the
instruction completes at cycle 8,270.

### Executed blocks and counts

| Block | Count | First cycle | Last cycle | Meaning |
|---:|---:|---:|---:|---|
| `1325` | 1 | 0 | 0 | configuration entry |
| `132b` | 1 | 5 | 5 | branch on `e795` value |
| `30f9` | 1 | 10 | 10 | zero-configuration entry |
| `3119` | 1 | 17 | 17 | selected source table |
| `2f51` | 32 | 30 | 348 | two 16-byte copy loops |
| `3141` | 1 | 370 | 370 | zero-configuration return |
| `17cf` | 2 | 376 | 2,761 | two DC323 groups |
| `17fc` | 512 | 384 | 3,279 | reset delay, 256 iterations per group |
| `bb5f` | 4 | 1,439 | 4,319 | direct-register table loader |
| `bb63` | 80 | 1,445 | 4,661 | 40 direct records per pair of groups |
| `bb76` | 4 | 2,303 | 4,823 | I/D table loader |
| `bb7e` | 36 | 2,311 | 5,118 | 18 I/D records per pair of groups |
| `1355` | 8 | 5,157 | 5,172 | wait for T0 to return low |
| `135a` | 1,536 | 5,174 | 8,254 | fixed inner delay loop |
| `135c` | 6 | 5,686 | 8,256 | fixed outer delay loop |
| `136d` | 1 | 8,268 | 8,268 | write checkpoint zero |

Blocks `3102` through `3116` have count zero.  Reconstructed byte `30ff=80`
is an unconditional `SJMP 3119`; it skips the apparent frame-request,
`$21.3` wait, `4c00` read, and conditional table selection shown by a stale
disassembly of the unreconstructed dump.

### Branch decisions

| Branch PC | Condition | Observed value | Outcome | Hardware dependency |
|---:|---|---|---|---|
| `132b` | `JNZ 1334` after `MOVX E795` | `A=00` | not taken; set `$20.5`, call `30f9` | shared-RAM configuration byte |
| `30ff` | `SJMP 3119` | opcode `80 18` | always selects ROM table at `3162` | none |
| `134f` | wait while T0 high | T0 low on first sample | proceeds | `P10 HSYNC H` phase |
| `1352` | wait while T0 low | high reached after 3 cycles | proceeds | `P10 HSYNC H` phase |
| `1355` | wait while T0 high | seven high samples, then low | proceeds at cycle 5,172 | `P10 HSYNC H` phase |
| `135a` | `DJNZ R0` | 256 iterations per outer pass | 1,536 iterations | deterministic register loop |
| `135c` | `DJNZ R1` | initial `R1=06` | 6 iterations | deterministic register loop |
| `1362` | `JNZ 1362` on TH0 | `TH0=00` | proceeds | T0 edge count; failure hangs |
| `1366` | `CJNE A,#61,1366` | `TL0=61` | proceeds | T0 edge count; failure hangs |

There were no entries at external-interrupt vector `0003` or timer-0 vector
`000b`, and therefore no interrupt return in the bounded interval.

### Relevant external accesses

- Cycle 2: read `E795=00`; this is the only external read that affects path
  selection.
- Cycles 14–364: write DC7051/control state, including 32 copied bytes at
  `F080–F08f` and `F0a0–F0af`.
- Cycles 381–5,137: write DC323 reset, direct-register, data, and I/D-command
  registers.  There are no reads of DC323 status in either group.
- Cycle 8,268: write `7ff2=00`.

During table loading P2 remains `f0`.  P1 supplies the high byte of each
16-bit DC323 access and is therefore the source of the observed DAT9 changes.
The P3 latch remains released; physical P3.4/T0 alternates with horizontal
timing.  No P1, P2, or P3 read other than the T0 bit tests changes control
flow.

## Configuration-table report

### Call graph and selected tables

```text
132f -> 30f9
          reconstructed 30ff: SJMP 3119
          ROM 3162-3181 -> F080-F08f, F0a0-F0af
133a -> 17cf
133d -> 17cf                 (identical second group)
          17f4               reset sequence
          bbb8               F072 control write
          bb91               zero I/D command
          bb5f(E0d7)         23 direct DC323 registers
          bb5f(E11d)         17 direct DC323 registers
          bb76(E185)          5 I/D commands
          bb76(E195)         13 I/D commands
```

The zero-configuration copy produces:

```text
F080: 00 33 5c 93 6c 93 cc 77 44 55 59 75 69 75 99 cc
F0A0: 00 3c 22 c3 3c cc c3 77 44 59 44 95 59 99 95 cc
```

### Direct DC323 tables

Each record is `register=16-bit value`, with P1 carrying the high byte and the
MOVX data byte carrying the low byte.

```text
E0D7 (23 records)
01=0000 02=0000 10=0000 11=01e0 12=01f4 13=0000
2f=3fff 30=3fff 35=014d 36=0340 37=020a 38=2010
39=003e 3a=3888 3b=49ce 3c=29dc 3d=31fc 3e=0000
3f=00a0 31=11f3 32=21f4 33=31fa 34=020d

E11D (17 records)
09=0080 15=0000 16=0000 17=0000 18=0000 19=0000
1a=0000 1b=0000 1c=0400 1d=0000 1e=0800 20=0008
21=0014 27=0000 28=0000 2a=1fff 2b=1fff
```

Direct records are normally 21 cycles apart.  `bb5f` only fetches ROM bytes,
writes P1, performs MOVX, and decrements the ROM count.  It cannot observe
DC323 ready, busy, completion, interrupt, or frame state.

### I/D command tables

| ROM table | Data values | Commands |
|---|---|---|
| `E185` | `0000 0004 0001 ffff ffff` | `0180 0181 0183 0188 0189` |
| `E195` | `00ca 00cc 00ca 00c0 0000 0000 ffff 0021 0021 0000 0034 0034 0000` | `0184 0185 0186 0187 018b 018e 018f 0190 0191 0192 0194 0195 0196` |

Each group submits the same 18 commands.  Consecutive command writes are
normally 24 cycles apart, with a 38-cycle boundary between `0189` and `0184`.
The groups enter at relative cycles 376 and 2,761.  Their command ranges are
2,330–2,752 and 4,715–5,137 respectively.

`bb76`, like `bb5f`, contains no poll or conditional wait.  Separate E4
routines `bb9a`, `bba4`, and `bbae` poll DC323 status bits 2, 4, and 5, but
none is called before `136d`.  The earliest instruction where a physical
input can alter the post-table path is therefore the T0 test at `134f`, after
both groups have completed.  No physical input can lengthen either successful
`17cf` call.

## DAT9 electrical audit

Schematic sheets 1, 2, and 10 show one named net, `P2 DAT9/TSTATUS H`, at all
three devices.  No PAL, buffer, or transceiver lies between the CPU2 P1.1 pin,
the CPU1 T1 pin, and DC323 DAT09.

| Device | Pin | Drive type | Output-enable condition | Contribution to DAT9 |
|---|---|---|---|---|
| CPU1 E57 8031 | P3.5/T1, pin 15 | quasi-bidirectional port; alternate T1 input | firmware releases with latch 1; latch 0 pulls low | handshake request and live input sample |
| CPU2 E24 8031 | P1.1, pin 2 | quasi-bidirectional port | latch 1 releases/weakly pulls up; latch 0 pulls low | handshake response and DC323 data bit 9 during writes |
| DC323 E70 | DAT09, pin 66 | bidirectional data-bus pin; output only for a selected read, otherwise input/high impedance | DC323 selected by `P3 DS L` with the board read cycle | status/data bit during reads; receives CPU2 P1.1 during writes |

The MAME MCS-51 core implements this distinction correctly for ordinary port
reads: `p1_r()` and `p3_r()` AND the output latch with the external callback,
so an external low is visible only when the port latch is released high.  P3
also ANDs the dedicated T0/T1 input-line state into the same physical port
read.

A PC-independent board model should maintain explicit DAT8–15 ownership:

1. On a CPU2/DC323 write cycle, CPU2 P1 is the bus source and DC323 is an
   input.  CPU1 T1 observes the resolved DAT9 level.
2. On a selected DC323 read cycle, CPU2 releases P1 to `ff`, DC323 drives the
   bus, and CPU1 T1 observes DC323 DAT9.
3. Outside a selected transaction, DC323 is high impedance.  CPU1 and CPU2
   port contributions resolve low if either quasi-bidirectional latch pulls
   low; otherwise the net is high.
4. The same resolved level must feed CPU1 P3.5 reads, CPU1's T1 input line,
   and CPU2 P1.1 reads.

Current discrepancies are bounded but real:

- `cpu2_p1_r()` substitutes DC323/status phases at firmware PCs `126f`,
  `1297`, `129a`, and `1700` instead of deriving them from a selected bus read.
- The dedicated CPU1 T1 input line follows CPU2's P1.1 latch but does not
  separately include a DC323 read driver.  Direct CPU1 P3.5 polling obtains
  the peer latch through `cpu1_p3_r()`, which is the path used here.
- Narrow-pulse retention at CPU1 `3925` and CPU2 `1711` is a scheduling
  compatibility accommodation rather than an electrical storage element.

These discrepancies affect reset/status reads and possible counter use.  They
do not isolate table writes: during both `17cf` groups CPU2 is the legitimate
bus driver, and its P1.1 changes must reach CPU1 on the real board.

## Cross-CPU DAT9 timeline

| Time (s) | Source | CPU2 PC | CPU1 PC | DAT9 event | Class | CPU1 interpretation |
|---:|---|---:|---:|---|---|---|
| 8.220509 | CPU1 P3.5 | near `1322` | `3b90` | high→low, pulse 5 | A | request releases sixth CPU2 rendezvous |
| 8.220521 | CPU1 P3.5 | configuration entry | `3b98` | low→high | A | request ends |
| 8.221939 | CPU2 P1.1 | `bb96` | `3bae` | high→low | B and C | accepted as response 5 |
| 8.222091 | CPU2 P1.1 | `bb6b` | `3bbc` | low→high | B and C | response 5 completes |
| 8.222133–8.225501 | CPU2 P1.1 | `bb6b/bb82/bb8c` | `3b6e/3b70` or interrupt | multiple table-data edges | B | not sampled; CPU1 is pacing LK201 bytes |
| 8.225501 | CPU2 P1.1 | `bb8c` | `3b70` | final pre-checkpoint high→low | B | not sampled |
| 8.228776 | CPU2 | `136d` | `3b6e` | `7ff2=00` | mailbox | too early for CPU1's pending sentinel |
| 8.228791 | CPU2 P1.1 | `137f` | `3b6e` | final low→high | B | not sampled |
| 8.235677 | CPU1 P3.5 | later CPU2 test | `3b90` | high→low, pulse 6 | A | next request |
| 8.235689 | CPU1 P3.5 | later CPU2 test | `3b98` | low→high | A | request ends |
| 8.295622 | CPU2 P1.1 | `bb82` | `3bab` | high→low graphics-data edge | B and C | accepted as response 6 |
| 8.295742 | CPU2 P1.1 | `bb82` | `3bbf` | low→high graphics-data edge | B and C | response 6 completes |
| 8.295773 | CPU1 | — | `3a0d` | `7ff2=10` | mailbox | overwrites the fast-path checkpoint; bounded timeout begins |

CPU1 routine `3ba0–3bce` polls the live P3.5 level: low at `3bab`, then high
at `3bbc`.  It does not capture an edge with Timer 1.  The last pre-checkpoint
low ends 6.886 ms before pulse 6, so no electrical or emulated edge remains to
be consumed.  CPU1 accepts the 8.295622 transition because it is actively
level-polling when CPU2 legitimately drives DAT9 low as graphics data.

No synthetic transition in the driver creates response 6.  The scheduler
trigger responds to a real P1.1 falling edge; it does not change the net.
The PC-qualified status substitutions occur outside this response.  Existing
pulse retention can preserve a rendezvous pulse at a sampling boundary, but
does not manufacture any of the table-data transitions listed above.

## Configuration and timing dependencies

| Input | Source | Observed emulator value | Alternative | Cycle/timing effect |
|---|---|---|---|---|
| `E795` | shared RAM, written later by CPU1 | `00` | `01` takes `1334` and writes `F080=aa` | controlled run makes checkpoint 348 us earlier; rejected |
| reconstructed `30ff` | E3 ROM | unconditional `SJMP 3119` | apparent stale-dump path would read `4c00` and wait on `$21.3` | not a hardware input; coherent reconstructed ROM proves executed path |
| CPU2 T0 | DC7051 `P10 HSYNC H` | valid phase and 97 counted edges | different phase changes short alignment; wrong count hangs | cannot add 6.9 ms to a successful run |
| DC323 ready/status | DC323 selected read | not read on this path | polling routines exist elsewhere | zero effect before `136d` |
| DC323 interrupt/INT0 | DC323/timing logic | no vector entry | interrupt could affect other phases | zero observed effect before `136d` |
| frame/VSYNC | DC7051/DC323 timing | not read or waited on | skipped code at `3102–3116` appears frame-related | zero effect on executed path |

## Hypothesis assessment

### Rejected

- **Missing DC323 busy/ready delay:** the loaders are write-only; 36 commands
  are already spaced mostly 24 cycles apart, and no firmware-visible stall
  mechanism exists.
- **A skipped frame-boundary wait:** reconstructed firmware unconditionally
  jumps over the apparent wait and no interrupt services it.
- **Wrong `E795` path:** the only alternative reaches the checkpoint 348 us
  earlier.
- **CPU2 interrupt latency:** no interrupt entry occurs.
- **T0/HSYNC as a multi-millisecond successful delay:** its phase alignment is
  line-scale and its counted value is validated by infinite failure loops.
- **Graphics DAT9 edges are hidden from CPU1:** the schematic directly joins
  all three pins, and CPU2 is the bus owner during writes.
- **A synthetic response-6 edge:** the accepted edge is a native CPU2 P1 data
  transition at `bb82` while CPU1 is polling.

### Supported

- The first causal divergence remains the native timing order: CPU2 finishes
  a deterministic 8.270 ms pre-checkpoint path while CPU1 intentionally spends
  13.579 ms after response 5 pacing the LK201 command sequence.
- The existing emulator's PC-qualified DC323 status model is not a faithful
  general electrical model.  Replacing it with explicit bus ownership is a
  valid fidelity task, but present evidence says it will not fix this ordering.

### Resolved by the CPU1 follow-up

- The second LK201 block is unconditional after response 5; there is no
  firmware-visible condition that avoids or defers it.
- Response 5 is genuine CPU2-driven DAT9 activity from the first DC323 zero
  command and following direct-register data.
- The missed checkpoint does not deadlock permanently.  CPU1's bounded wait
  expires at 119.955290 s and native success path `4551` is reached at
  119.995547 s with the retained authentic `80` result.

## Investigation boundary

The CPU1 follow-up is documented in
`phase4-cpu1-entry-and-7ff2-report.md`.  Both executed CPU paths are now
bounded, the `7ff2` fast path and timeout fallback are understood, and no
timing or mailbox workaround is justified.  Further synchronization changes
require new external hardware or documentation evidence.  A separate fidelity
cleanup may still replace PC-qualified DC323 status with explicit bus
ownership, but it should not be presented as a startup-timing fix.

