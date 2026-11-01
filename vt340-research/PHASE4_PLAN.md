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

## Investigation sequence

1. Record every CPU2 P1.1 transition between the sixth rendezvous and `136d`,
   including the writing PC and the CPU1 sampling instruction.
2. Account for CPU1's time from response 5 through pulse 6, including the four
   internal-UART writes made by `3ac9`; timer-0 service has been bounded and
   ruled out as a sufficient explanation.
3. Account for CPU2's time from `1325` through `136d`, separating fixed CPU
   cycles, DC323/DC7051 waits, T0 measurements, and external-bus operations.
4. Compare those intervals with the board clocks and documented peripheral
   semantics. Treat a CPU-core timing defect, missing device latency, and an
   incorrect pin-level model as separate hypotheses.
5. Perform one bounded experiment at the identified physical boundary. Do not
   alter `7ff2` or branch at `3a19` as the production solution.
6. Implement the verified behavior, remove the experiment, and run repeated
   cold boots plus the Phase 2/3 regressions.

## Exit condition

An ordinary cold boot must place CPU1's `7ff2=10` request before the native
CPU2 acknowledgement, allow CPU1 to consume the authentic `80` result, and
continue stably without a PC-qualified timing or mailbox workaround.
