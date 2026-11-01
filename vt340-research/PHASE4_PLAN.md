# Phase 4 plan: DAT9 and mailbox synchronization

## Objective

Determine why CPU2 clears shared byte `7ff2` before CPU1 posts its startup
request, then implement only the physical signal, timing, or device behavior
that restores the firmware's intended request/acknowledgement order.

Phase 4 will not delay an acknowledgement at a firmware PC, force a mailbox
value, extend pulses indefinitely, or render `VT340 OK` directly.

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
| 8.295771 s | CPU1 posts `7ff2=10` |
| 8.309648 s | CPU1 emits notification pulse 7 |

CPU1 then waits at `3a18-3a21` for a zero that CPU2 already wrote. CPU2 later
posts authentic result `80`, but CPU1 cannot consume it without first seeing
the acknowledgement state.

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
microseconds before another command. No status poll is being prematurely
satisfied on the path from response 5 to `136d`.

### Timer-0 service is not sufficient to explain the ordering

A debugger-only experiment masked CPU1 `ET0` immediately after response 5.
Pulse 6 moved from 8.235659 s to 8.234513 s, only 1.146 milliseconds earlier,
and still occurred 5.734 milliseconds after CPU2's acknowledgement. Response
6 and the `7ff2=10` request remained tied to the same later CPU2 P1.1 table
transition at approximately 8.29575 s. Timer-0 delivery is therefore not the
immediate cause of the missed acknowledgement.

### Controlled scheduler-hack cleanup

Three interventions that no longer affect the observed startup path have been
removed from the normal driver:

- CPU1 is no longer configured as MAME's perfect-quantum device.
- The driver no longer imposes a 10 microsecond maximum scheduler quantum;
  MAME's default scheduling produces the same startup sequence.
- A CPU1 P3.5 edge at the `7ff2=10` report request no longer queues a retained
  DAT9/T1 pulse.  Retention remains limited to the existing CPU2
  `1701-1711` rendezvous while its pin-level replacement is investigated.

After each removal, the ROM-boundary audit and Phase 2/3 regression suites
passed.  With default scheduling, CPU2 acknowledged at 8.228779 s, CPU1
emitted pulse 6 at 8.235677 s, and CPU1 posted the request at 8.295773 s.
Three additional cold runs reproduced the 66.994 ms
acknowledgement-before-request gap and 6.898 ms pulse-6 delay exactly.  This
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
executes the original four-byte `3ac9` report block. SBUF writes occur 26 us,
3.491 ms, 6.650 ms, and 10.114 ms after response 5. Seven timer-0 services
occur before CPU1 reaches pulse 6 at 13.579 ms. The earlier timer-mask
experiment bounded those services at about 1.16 ms total; even without them,
the firmware's software delay remains about 12.4 ms.

CPU2 therefore clears `7ff2` 6.681 ms after response 5, while CPU1 cannot
emit pulse 6 until 13.579 ms after that response. The 6.898 ms ordering gap is
the direct result of executed firmware loops and table transfers. No missing
MAME scheduling interval or unaccounted interrupt explains it.

The complete startup trace also rejects an off-by-one rendezvous count. The
special CPU1 startup exchange releases CPU2's first `1701` call; CPU1 report
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
acknowledgement-before-request lead. It is a remaining fidelity item, not a
candidate correction for this ordering failure.

### Mailbox lifecycle

`traces/phase4-mailbox-lifecycle.lua` records every CPU1 and CPU2 access to
`7ff2`. After the destructive POST/shared-memory tests, the complete startup
transaction is:

| Emulated time | Processor/PC | Operation |
|---:|---|---|
| 8.228779 s | CPU2 `136e` | write `00` |
| 8.295773 s | CPU1 `3a0e` | write request `10` |
| 8.295773-13.194725 s | CPU1 `3a19` | repeatedly read `10` |
| 13.194725 s | CPU2 `163f` | write result `80` |
| after 13.194725 s | CPU1 `3a19` | repeatedly read `80` |

CPU2 does not read `7ff2` during this exchange, no second CPU2 zero is
written, and CPU1's first-stage loop requires zero before its second-stage
result wait can consume `80`. Thus `136d-136e` is the sole native
acknowledgement for this request/result protocol. The failure is a strict
ordering error, not a mistaken classification of an initialization clear.

### Remaining rendezvous suspension is not the cause

The driver still suspends CPU1 at a falling P3.5 edge while CPU2 is polling
at `170e`, then resumes it when CPU2 consumes the edge. A controlled build
removed that `spin_until_trigger` call without changing the retained-pulse
logic. The complete handshake trace was unchanged: response 5 remained at
8.222098 s, `136d` at 8.228776 s, pulse 6 at 8.235677 s, and response 6 at
8.295750 s. The intervention was restored after the experiment.

This also exposes a stronger constraint on the next hypothesis. CPU1 cannot
write request `10` until it accepts response 6, but the CPU2 table transition
currently accepted as response 6 is executed after `136d`. Uniform CPU2
slowdown or ordinary per-access wait states cannot reverse two events in the
same processor's program order. A viable board-timing explanation must affect
the visibility or commit order of the `136d` external write, or cause CPU1 to
accept a different earlier DAT9 transition.

## Investigation sequence

1. Trace `P3 MC/R H`, `P3 ARB*`, and the E58 PAL paths around shared E93/E94
   RAM. Determine whether a CPU2 MOVX write can be held, masked, or committed
   later while CPU1 owns the memory bus; a simple CPU stall is insufficient.
2. Trace every DAT9 falling edge from pulse 5 through response 6 against CPU1's
   timer/counter state. Determine whether physical edge capture, rather than
   port-level polling, should let CPU1 consume a different earlier transition.
3. Verify the exact 8031 external-input and MOVX semantics against the board
   part and compare them with the MAME MCS-51 core.
4. Perform one bounded experiment at the first identified visibility or
   commit boundary. Do not
   alter `7ff2` or branch at `3a19` as the production solution.
5. Implement the verified behavior, remove the experiment, and run repeated
   cold boots plus the Phase 2/3 regressions.

## Exit condition

An ordinary cold boot must place CPU1's `7ff2=10` request before the native
CPU2 acknowledgement, allow CPU1 to consume the authentic `80` result, and
continue stably without a PC-qualified timing or mailbox workaround.
