# Phase 4 plan: DAT9 and mailbox synchronization

## Current status

Phase 4 has achieved the visible and functional boot result: native POST
returns `00`, `Wait` is erased, and firmware displays persistent `VT340 OK`.
It has not achieved the fast-path synchronization requirement. CPU2 still
writes `7ff2=00` approximately 67 ms before CPU1 writes its stale-zero guard
`10`; CPU1 therefore advances only after the ROM timeout at 119.955290 s.

The remaining Phase 4 objective is narrowly the authentic fast checkpoint.
Serial diagnostics, NVRAM, packet draining, banner rendering, clear/erase,
and interactive terminal operation are completed dependencies, not candidate
explanations for the delay.

The apparent 120-second duration has now been audited independently. The
`3a18-3a1f` fallback performs 2^24 iterations of `MOVX`, `JZ`, and `DJNZ`,
plus the two outer `DJNZ` levels. At 12 MHz its bare duration is exactly
100.794880 seconds. A controlled run that masks Timer 0 only after entering
the already-missed checkpoint wait measures that exact value; normal timer
service adds 10.850739 seconds, and the preceding 8.31 seconds of startup
places success at 119.995544 seconds. This validates CPU timing and confirms
that the delay must be removed by restoring the checkpoint order, not by
shortening the firmware fallback. See
`traces/phase4-timeout-cost-summary.txt`.

## Objective

Determine why CPU2 publishes the shared `7ff2` checkpoint zero before CPU1
installs its pending sentinel, then implement only the physical signal,
timing, or device behavior that restores the firmware's intended
sentinel/checkpoint/result order.

Phase 4 will not delay a checkpoint at a firmware PC, force a mailbox
value, extend pulses indefinitely, or render `VT340 OK` directly.

For interactive use only, the driver now exposes an optional ROM compatibility
patch that changes CPU1's pending value from `10` to `00`. This takes the
existing fast path while retaining CPU2's native final result and CPU1's
`80` validation. It is disabled by default, separately documented in
`firmware/fast-start-patch.md`, and is not considered a Phase 4 hardware fix.

## Starting boundary

The corrected Phase 3 baseline is deterministic:

| Emulated time | Event |
|---:|---|
| 8.220490 s | CPU1 emits handshake pulse 5 |
| 8.220493 s | CPU2 returns from its sixth `1701` rendezvous |
| 8.220495 s | CPU2 begins configuration at `1325` |
| 8.222080 s | CPU1 accepts P1.1 activity as response 5 |
| 8.228776 s | CPU2 clears `7ff2` at `136d` |
| 8.228786-8.228791 s | CPU2 writes P1 low/high around a DC323 transfer |
| 8.235659 s | CPU1 emits handshake pulse 6 |
| 8.295748 s | CPU1 accepts later P1.1 activity as response 6 |
| 8.295771 s | CPU1 installs pending sentinel `7ff2=10` |
| 8.309648 s | CPU1 emits notification pulse 7 |

CPU1 then waits at `3a18-3a21` for a zero that CPU2 already wrote. CPU2 later
posts authentic result `80`, but CPU1 cannot consume it without first seeing
the checkpoint state.

## Findings from the opening audit

### Scheduler ordering is not the cause

The event order is stable with maximum scheduler quanta of 1, 10, and 100
microseconds. Removing CPU1 perfect-quantum scheduling also leaves the order
unchanged. The largest observed movement in the recorded boundary is about 20
microseconds, far smaller than the roughly 7 millisecond lead of CPU2's clear
over CPU1 pulse 6.

### The sixth CPU2 rendezvous is not consuming a stale pulse

CPU2 enters its sixth `1701` call at 4.719225 s and remains at `170e` until
CPU1 emits pulse 5 at 8.220490 s. The retained-pulse mechanism therefore does
not prematurely release this call.

### DAT9 is a direct multiplexed net

The schematic connects CPU2 P1.1 (`P2 DAT9/STATUS H`) directly to CPU1 T1.
The transitions seen during video-table transfers are real electrical changes
on the same pin, not a separately gated handshake channel. A fix must preserve
that multiplexed behavior.

### Immediate DC323-ready latency is not the missing interval

The two startup table loaders deliberately enter at `bb5f` and `bb76`, after
the optional Address Output Complete polls at `bba4`. They issue I/D commands
about 24 microseconds apart; the Dragon specification requires only about 3
microseconds before another command. A command-level trace now counts exactly
18 I/D commands in each `17cf` group, 36 total. Consecutive commands are
normally 24 microseconds apart, with one 38 microsecond gap between `0189`
and `0184`; each complete group lasts 2.383 milliseconds. Existing spacing
is already about eight times the documented minimum, so omitted immediate
ready latency cannot supply the roughly 6.9 milliseconds needed to reverse
the mailbox order. No status poll is being prematurely satisfied on the path
from response 5 to `136d`. The exact sequence is recorded in
`traces/phase4-table-command-summary.txt`.

### Timer-0 service is not sufficient to explain the ordering

A debugger-only experiment masked CPU1 `ET0` immediately after response 5.
Pulse 6 moved from 8.235659 s to 8.234513 s, only 1.146 milliseconds earlier,
and still occurred 5.734 milliseconds after CPU2's checkpoint. Response
6 and the `7ff2=10` sentinel remained tied to the same later CPU2 P1.1 table
transition at approximately 8.29575 s. Timer-0 delivery is therefore not the
immediate cause of the missed acknowledgement.

### Controlled scheduler-hack cleanup

Three interventions that no longer affect the observed startup path have been
removed from the normal driver:

- CPU1 is no longer configured as MAME's perfect-quantum device.
- The driver no longer imposes a 10 microsecond maximum scheduler quantum;
  MAME's default scheduling produces the same startup sequence.
- A CPU1 P3.5 edge near the `7ff2=10` sentinel write no longer queues a retained
  DAT9/T1 pulse.  Retention remains limited to the existing CPU2
  startup pulse consumed by CPU1's initial diagnostic wait.
- The PC-qualified CPU1-pulse latch at CPU2 `1711` is also gone. Explicit DAT9
  resolution plus timeslice handoff preserves all six native rendezvous without
  it; Phase 3 passes and the Phase 4 boundary remains exactly 6.900 ms.
- The opposite-direction startup retention at CPU1 `3925` is not redundant.
  Without it, CPU2 releases its first low response 8.553 ms before CPU1 starts
  sampling and CPU1 takes fatal path `3933`. This exposes a real unresolved
  startup phase/timing mismatch; see
  `traces/phase4-initial-pulse-retention-summary.txt`.

A reset-relative trace now accounts for that entire lead. CPU2 asserts DAT9
at 6.478 ms after reset release, following DC323 reset/table initialization
and a 4.31 ms internal-RAM test, and releases it at 6.981 ms. CPU1's native
four-byte LK201 block delays its first response sample until 15.534 ms.
Schematic sheets 1-3 show CPU1 P1.0 wired directly to CPU2 RST and CPU2 driven
by ungated 12 MHz CPUBCLK, so neither a board reset delay nor a slower CPU2
clock is supported. `traces/phase4-reset-to-first-dat9.lua` captures the path;
`traces/phase4-initial-pulse-retention-summary.txt` records the result.

During this audit, live debugger reads of P1/P3 were found to invoke the
driver callbacks and consume modeled DAT9 phases. Port-read side effects are
now suppressed whenever MAME marks the access side-effect-free. Live-port
tracing consequently reproduces the same 6.478/6.981/15.534 ms timing as a
trace that does not inspect the ports.

After each removal, the ROM-boundary audit and Phase 2/3 regression suites
passed. With default scheduling, CPU2 published its checkpoint at 8.228779 s, CPU1
emitted pulse 6 at 8.235677 s, and CPU1 installed the sentinel at 8.295773 s.
Three additional cold runs reproduced the 66.994 ms
checkpoint-before-sentinel gap and 6.898 ms pulse-6 delay exactly. This
rules out all three removed interventions as the source of the current fault.

### Firmware interval breakdown

`traces/phase4-interval-breakdown.lua` measures the two racing paths with
emulation time, actual CPU1 SBUF writes, interrupt-vector entries, and CPU2
video-aperture writes. The CPU2 path from configuration entry to the early
mailbox clear is fully accounted for:

| CPU2 interval | Elapsed |
|---|---:|
| `1325` entry to reconstructed `30f9` entry | 10 us |
| Zero-configuration table load, `30f9-3141` | 360 us |
| First `17cf` table group | 2.383 ms |
| Second `17cf` table group | 2.383 ms |
| T0 edge synchronization | 20 us |
| Fixed `r1=06`, `r0=00` timer loop | 3.084 ms |
| Timer validation and `136d` clear | 10 us |
| **Configuration entry to `136d`** | **8.268 ms** |

CPU1 accepts response 5 1.587 ms after CPU2 enters configuration. It then
executes the original four-byte `3ac9` LK201 command block. SBUF writes occur 26 us,
3.491 ms, 6.650 ms, and 10.114 ms after response 5. Seven timer-0 services
occur before CPU1 reaches pulse 6 at 13.579 ms. The earlier timer-mask
experiment bounded those services at about 1.16 ms total; even without them,
the firmware's software delay remains about 12.4 ms.

CPU2 therefore clears `7ff2` 6.681 ms after response 5, while CPU1 cannot
emit pulse 6 until 13.579 ms after that response. The 6.898 ms ordering gap is
the direct result of executed firmware loops and table transfers. No missing
MAME scheduling interval or unaccounted interrupt explains it.

The complete startup trace also rejects an off-by-one rendezvous count. The
special CPU1 startup exchange releases CPU2's first `1701` call; CPU1 handshake
pulses 1-5 release calls 2-6. The low transitions that CPU1 accepts as later
responses are generated by the following CPU2 table operations on the
multiplexed P1/DAT9 bus.

### Schematic signal and clock audit

The February 1987 VT340 schematic confirms that CPU2 P1.1, CPU1 T1, and
DC323 DAT09 are directly connected to the same `P2 DAT9/TSTATUS H` net. There
is no intervening transceiver-enable or handshake-only gate between CPU2 P1.1
and CPU1 T1. The P1.1 transitions generated by the table loaders therefore
are physically visible to CPU1 and cannot be discarded as an emulation-only
alias.

Both processors derive their clock from the same 12 MHz oscillator, but the
paths are not identical. CPU2 `CPUBCLK` is an ungated derived clock. CPU1
`CPUACLK` passes through logic controlled by `P3 MC/R H`, so the board can
stop CPU1 during memory-controller ownership. Modeling that gate could only
delay CPU1 relative to CPU2, however, and would increase the current
checkpoint-before-sentinel lead. It is a remaining fidelity item, not a
candidate correction for this ordering failure.

A controlled 8 MHz CPU2 build independently rejects clock skew as a workaround.
CPU2 reaches its native T0 validation with `TL0=91`, exactly the `12/8` scaling
of the required `61`, and loops at `1366` before publishing a checkpoint. The
production driver was restored to 12 MHz after the experiment. See
`traces/phase4-clock-ratio-summary.txt`.

### `7ff2=10` is a pending sentinel, not a CPU2 request

`traces/phase4-mailbox-lifecycle.lua` records every CPU1 and CPU2 access to
`7ff2`. After the destructive POST/shared-memory tests, the complete startup
transaction is:

| Emulated time | Processor/PC | Operation |
|---:|---|---|
| 8.228779 s | CPU2 `136d` | write checkpoint `00` |
| 8.295773 s | CPU1 `3a0d` | write pending sentinel `10` |
| 8.295773-13.194725 s | CPU1 `3a19` | repeatedly read `10` |
| 13.194725 s | CPU2 `163f` | write result `80` |
| after 13.194725 s | CPU1 `3a19` | repeatedly read `80` |

The complete ROM cross-reference strengthens the trace result: CPU2 never
reads `7ff2`. CPU1 `3a0d` installs `10` so its first-stage loop at `3a18` can
distinguish CPU2's checkpoint zero from the later final result. CPU2 writes
that zero at `136d`, writes success `80` at `163e`, and has error writers at
`159f`, `197a`, and `1b24`. CPU1's `3a31` loop accepts the final nonzero value,
`3a3a` tests for success `80`, and `3aaf` maps other values to error reports.

Thus `10` neither requests work nor notifies CPU2, and zero does not
acknowledge a CPU2 read. CPU2 publishes its sole checkpoint zero before CPU1
installs the stale-zero guard, so CPU1 overwrites the checkpoint and loses the
fast path. The first loop is bounded, however: an unmodified long run exits it
at 119.955290 s and reaches native success at 119.995547 s using the retained
`80`. The cross-reference and timeline are recorded in
`traces/phase4-mailbox-semantics-summary.txt`.

### Rendezvous suspension was redundant and has been removed

The driver formerly suspended CPU1 at a falling P3.5 edge while CPU2 was
polling at `170e`, then resumed it when CPU2 consumed the edge. A controlled
build removed that `spin_until_trigger` call without changing the retained-
pulse logic. The complete handshake trace was unchanged: response 5 remained
at 8.222098 s, `136d` at 8.228776 s, pulse 6 at 8.235677 s, and response 6 at
8.295750 s. The production driver now omits the suspension and its otherwise
unused scheduler trigger calls.

This also exposes a stronger constraint on the next hypothesis. CPU1 cannot
write pending `10` until it accepts response 6, but the CPU2 table transition
currently accepted as response 6 is executed after `136d`. Uniform CPU2
slowdown or ordinary per-access wait states cannot reverse two events in the
same processor's program order. A viable board-timing explanation must affect
the visibility or commit order of the `136d` external write, or cause CPU1 to
accept a different earlier DAT9 transition.

### DAT9 is level-polled and no earlier edge is pending

`traces/phase4-dat9-edge-summary.txt` records every DAT9 bit transition in
the critical interval. CPU1 routine `3ba0-3bce` does not use Timer 1 edge
capture: it polls live P3.5, first waiting for low at `3bab` and then for high
at `3bbc`. Response 5 is the low/high interval at 8.221939-8.222091 s.

CPU1 then executes the four-byte `3ac9/3b64` LK201 command delay and is not polling
DAT9 during the table-data transitions that follow. The final pre-ack low is
held from 8.225501 through 8.228791 s, but CPU1 does not emit pulse 6 and
enter the next low-level wait until 8.235677 s. There is therefore no physical
edge or retained level for an exact 8031 input model to recover. The next
accepted low is the later CPU2 table transition at 8.295622 s.

This rules out Timer 1 edge-capture semantics as the missing behavior and
confirms that direct DAT9 visibility alone reproduces the failure.

### Controlled sentinel-visibility experiment

`traces/phase4-request-visibility-experiment.lua` performs one debugger-only
experiment at the mailbox decision boundary. Immediately after CPU1 executes
its authentic pending `7ff2=10` write, the script restores the already-issued
checkpoint zero;
it does not alter either CPU's PC and does not inject a result or display
command.

Original CPU1 firmware then accepts zero at 8.309677 s, enters its native
result wait, observes CPU2's authentic `80` at 13.194736 s, and continues
through `4551`. This proves that preserving the earlier zero across CPU1's
sentinel write is sufficient to clear the immediate Phase 4 blocker. It does
not prove that the real board suppresses, delays, or redirects that write.
The schematic/PAL ownership path must establish such semantics before any
driver change is justified.

With the driver restored to the schematic-correct I8031, the controlled path
subsequently reaches the separately documented upper-stack problem before
`41f7`. That later issue is no longer hidden by an I8032 substitution and is
not evidence against the mailbox result.

### Recovered PAL equations reject write suppression

The actual `23-168K5` E58 PAL16R8 and `23-335J5` E78 PAL16L8 fuse maps are
now recovered and decoded in `hardware/pal-analysis.md`. E58 asserts `WDS L`
for the observed CPU1 MOVX write state. E78 then asserts shared-DRAM `MWR L`
when CPU1 `AWR L` and `WDS L` are active outside the I/O aperture. Both E93
and E94 therefore store CPU1's `7ff2=10` on the real board.

The visibility experiment remains useful as a dependency proof, but its
implied hardware behavior is ruled out and must not be implemented. The
remaining viable ordering mechanism is before `136d`: CPU1 must reach pulse 6
while CPU2 is still producing pre-ack table/DAT9 transitions. The next audit
returns to the duration and bus ownership of the DC323 table-transfer path.

### All recovered PALs are now assigned

The terminal-control parts list places its two J5 PALs at E16 and E78, not E15
and E78. E15 is a bitmap DRAM. The remaining `23-336J5` fuse map is E16 and
matches the output-map/palette address decoder shown on the schematic. Its
pins carry CPU2 address, read/write, `AIOSEL`, and `WDS` signals; it has no
DAT9/TSTATUS connection.

The DC323 select is E78's `P3 DS L` output. Together with the direct-net audit,
this rules out a missing PAL-controlled DAT9 ownership interval. The recovered
PAL set now accounts for shared-memory control, DC323 selection, and output-map
decoding without revealing any hardware mechanism that can reorder the two
mailbox writes.

### Critical ROM boundaries remain coherent

The independent 9track `23-236E6` E49 image is byte-for-byte identical to the
Avitech E49 dump used by this project. That does not identify the E1-E5
cartridge revision, but it confirms both physical sources carry the same
graphics character ROM.

The two reconstructed boundaries on the immediate CPU2 configuration path are
also independently constrained by instruction and table structure. E3
`30ff=80` forms the coherent `SJMP 3119`. The first E4 graphics table crosses
logical `60ff`: raw `6000=3a` produces the ordered command/value record
`3a 38 88`, whereas the naive rotated raw `6100=c5` would introduce an invalid
command into that table. The known page-transition reconstruction is therefore
not adding the two `17cf` groups or their observed duration.

### Controlled keyboard-command-delay experiment identifies the immediate dependency

`traces/phase4-report-delay-experiment.lua` shortens only the two inner DJNZ
loops in the four-byte CPU1 keyboard command block immediately after response 5. It preserves
the SBUF writes, calls, stack operations, three-iteration outer loop, and both
processors' native control flow. CPU1 then emits pulse 6 at 8.222291 s,
accepts a native table transition as response 6 at 8.222432 s, and writes the
authentic `7ff2=10` sentinel at 8.222455 s. CPU2's unchanged `136d` write
clears it at 8.228779 s; CPU1 consumes that zero at 8.236053 s and later
consumes CPU2's authentic `80` result at 13.194734 s.

This is the smallest controlled timing experiment that restores the native
sentinel -> checkpoint -> `80` order. It is not a production fix. CPU1 configures
TMOD=`21`, TH1=`f3`, and PCON=`ff`; at the schematic 12 MHz clock that is
approximately 4807.7 baud, or 2.08 ms per 8N1 character. The approximately
3.07 ms software delay around each byte is plainly deliberate UART pacing.
The 8031 clock, instruction timing, and keyboard command loop must remain unchanged.
The complete method and timestamps are in
`traces/phase4-report-delay-summary.txt`.

### Full LK201 device does not alter the synchronization boundary

The VT240 driver identified MAME's existing ROM-driven `lk201_device`. CPU1's
four SBUF writes are LK201 traffic (`11 8f 13 8c` on this boot), not a report
to CPU2. The VT340 now connects CPU1 P3.1/TXD to the keyboard receive input and
the keyboard transmitter to CPU1 P3.0/RXD, replacing the synthetic power-on
byte timer.

With the exact LK201 ROM images, the Phase 4 interval trace is unchanged:
CPU2 writes checkpoint zero at 8.228779 s and CPU1 emits pulse 6 at
8.235679 s, leaving a 6.900 ms inversion. The real keyboard therefore improves
hardware fidelity but does not control the missing `10 -> 00 -> 80` ordering.
Exact hashes and comparison results are in
`traces/phase4-lk201-integration-summary.txt`.

### The public cartridge dump is a matched V1.1 set

The Avitech archive photographs show the terminal's installed rear cartridge
labeled `VT330/340 V1.1`; its opened-cartridge photographs show all five
E1-E5 devices on one PCB. E5 also contains localized `V1.1` setup-directory
text. The CPU1 and CPU2 images are therefore a matched V1.1 firmware set, not
an accidental cross-revision mixture.

DEC field-change order VT330-I001 required replacement of the V1.1 cartridge
with `VT330/340 V2.1`, part `70-22623-04 REV. C01`, because multiple V1.1
firmware bugs were corrected. The order does not identify this startup timing
as one of those bugs, so revision alone is not yet a causal explanation. No
public V2.1 E1-E5 dump has been located. A V2.1 dump or release note
`EK-VT3XX-RN-003` is now the strongest independent comparison for the
CPU1 `3b64` keyboard-command pacing and CPU2 `1325-136d` table path.

Sources: [Avitech VT340 internals](https://avitech.com.au/?page_id=1964) and
[DEC FCO VT330-I001](https://manx-docs.org/collections/mds-199909/cd2/fco/vt330i01.pdf).

The two most relevant DECnotes topics survive only as metadata. Inspection of
the archive directory shows no `NT/0056.nt` body file for the terminal
conference, so the missing replies are not recoverable from its 1.2 GB public
download. Public ROM inventories likewise contain no V2.1 E1-E5 set. The
search record and exact comparison targets are in `firmware/v21-search.md`.

### Extra table-duration threshold is too large for ordinary ready latency

With no public V2.1 image or release note located, the next controlled test
repeated CPU2's authentic first `17cf` table group before its native second
group. Four additional groups (+9.540 ms) are insufficient: pulse 6 occurs
after the last pre-ack table transition, and CPU1 still accepts the
post-`136d` transition before writing pending `10`. Five additional groups
(+11.925 ms) are sufficient: pulse 6 occurs during the final table group,
CPU1 accepts a pre-checkpoint transition, writes `10` at 8.236771 s, and then consumes
CPU2's authentic zero and `80` result.

This brackets the timing dependency but rejects the repetition as hardware
behavior. It requires five extra 18-command groups, not a small per-command
ready interval, and it works because table data continues toggling DAT9. A
generic stall that merely moves `136d` cannot provide the required response.
The script and exact timelines are in
`traces/phase4-table-duration-experiment.lua` and
`traces/phase4-table-duration-summary.txt`.

### CPU2 is launched by DAT9, not by `7ff2` or a missing `e795` update

`traces/phase4-control-launch.lua` follows both CPUs across the control
boundary. CPU1 pulse 5 releases CPU2's sixth `1701` rendezvous at `1322`, and
CPU2 reads shared `e795=00` at 8.220511 s. CPU1 does not compute and write
`e795=01` until 8.295768 s, immediately before installing pending `7ff2=10`.
CPU2's startup test is therefore already running under DAT9 control; neither
shared write launches it.

A controlled decision-point experiment supplied the later `e795=01` value at
CPU2 `1325`. CPU2 took its authentic nonzero branch, but wrote checkpoint zero
0.348 ms earlier and final result `80` about 4.43 seconds earlier. CPU1 still
missed the checkpoint. The executed zero-path selection is not the missing
delay or synchronization behavior, and no `e795` forcing belongs in the
driver. Exact traces are in `traces/phase4-config-race-summary.txt`.

Schematic page 18 identifies CPU1 P1.6 as the firmware-driven
`P1 CPMRESET H` output. The driver returns the live 8031 P1 latch, so the low
value used to compute `e795=01` is not a missing external strap or input.

## Investigation sequence

### Completed bounded pre-checkpoint investigation

The bounded `1325-136d` trace and schematic DAT9 audit reached **Outcome D**:
no qualifying CPU2 wait, configuration input, interrupt, or DAT9 isolation
mechanism exists on the executed path. The write begins at machine cycle 8,268
and completes at 8,270. Both `17cf` groups are deterministic write-only table
loaders, and reconstructed `30ff=80` skips the apparent frame wait. T0/HSYNC
only supplies short phase alignment and a validated edge count. The shared
DAT9 net makes CPU2 graphics-data transitions legitimately visible to CPU1.
See `traces/phase4-precheckpoint-dat9-report.md` and the reproducible bounded
trace `traces/phase4-precheckpoint-path.lua`.

The upstream CPU1 investigation is complete. The response-5 return at `3bce`
flows directly to the second `LCALL 3b9a` at `39ef`; the `11 8f 13 8c` block
has no hardware-dependent branch, UART-status wait, or keyboard-response
dependency. Response 5 is the genuine CPU2 P1.1 low/high sequence produced by
the first DC323 zero command and direct-register high byte. See
`traces/phase4-cpu1-entry-and-7ff2-report.md` and the diagnostic-only script
`traces/phase4-cpu1-lk201-entry.lua`.

The same audit reconstructs all `7ff2` readers and writers, including indirect
destructive RAM tests. CPU1's `10` invalidates their stale zero, the first wait
prefers a new CPU2 zero, and the second wait prefers a nonzero terminal result.
The normal `10 -> 00 -> 80` order is therefore a proved fast-path firmware
contract, not an assumed three-state interpretation. It is not mandatory for
eventual success because the checkpoint wait has a long timeout fallback.

1. Treat the CPU1 command path, response-5 source, and `7ff2` state semantics
   as closed unless new physical evidence contradicts the bounded traces.
2. Require new external evidence—a real-hardware capture, service document, or
   independently sourced firmware behavior—before proposing a synchronization
   mechanism absent from both executed CPU paths.
3. The operational PC-qualified DC323 bit-0 substitution has been removed.
   Native `fe`/`fd` acknowledgements now release INT0 and CPU2 drains every
   startup ring packet. The former POST-only register-7 and ready substitutions
   at `1bd1`, `2900`, and `bba0-bbb4` have also been removed: the standalone
   DC323 now supplies diagnostic data and completion state from device events.
   See `traces/dc323-post-shim-cleanup-report.md`.
4. Implement only verified physical behavior, remove all forcing, and run
   repeated cold boots plus the Phase 2/3 regressions.

A V2.1 image remains useful as an optional comparison if a new artifact is
supplied, but board/ROM-revision speculation is not an active investigation
branch.

## Exit condition

### Current late-boot result

The firmware now passes every modeled startup diagnostic. Command-32 PBT
`0bc4` streams the E49 startup strings through the documented DC323 register-7
FIFO. Correct E80, SCN2681, and SCN2641 behavior produces CPU1 result `00`,
and the original renderer displays persistent `VT340 OK` after the documented
frame-boundary erase. These results are covered by the Phase 4 peripheral,
PBT, ring-drain, and graphics regressions.

An ordinary cold boot must place CPU1's `7ff2=10` pending sentinel before the
native CPU2 checkpoint zero, allow CPU1 to consume the authentic `80` result,
and continue stably without a PC-qualified timing or mailbox workaround. The
current driver satisfies only the final stability clause: it misses the zero
and reaches the same result through the approximately 120-second timeout.
