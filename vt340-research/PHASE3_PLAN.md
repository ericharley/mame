# Phase 3 plan: find the real startup completion event

> **Closed 2026-10-31.** Dispatcher, stack, ROM execution, CPU2 reset, and
> low-ROM-to-E4 integrity are verified. The remaining DAT9/`7ff2` ordering
> fault is Phase 4 synchronization work. See `PHASE3_CLOSEOUT.md`.

## Archived objective

Identify the physical device state or interprocessor event that should move
CPU1 from the `B.6` retry path into command 32 and subsequently make CPU2's
command-32 handler observe a non-empty ring at `dc02`. Implement only the
verified hardware semantics that produce those transitions, then demonstrate
an unforced cold boot beyond `Wait`.

Phase 3 did not add raster features or render `VT340 OK` directly. It remained
focused on firmware control flow, peripheral status, interrupts, and CPU
synchronization.

## Progress update: 2026-10-31

### Full ROM-boundary audit

The earlier list of isolated ROM repairs was incomplete. The published dumper
mechanism affects every 256-byte transition, not only boundaries already
reached by failing execution. The driver now reconstructs all 126 recoverable
`xxff` positions in each E1-E5 image from raw `xx00`, changing 613 values, and
then rebuilds the five missing checksum tails. This generalized reconstruction
reproduces every previously proven repair and newly restores E1 `38ff=78` and
CPU1 `3aff`.

E1 `38ff=78` restores the coherent `MOV R0,#55 / LCALL 3B63 / CLR RI /
MOV A,SBUF` stream followed by `CLR P1.0`. Schematic sheets 1 and 2 show P1.0
driving CPU2's active-high reset directly, which is now modeled. CPU1 releases
CPU2 at 0.558338 s, and the native DAT9 rendezvous succeeds at 0.573882 s.
This supersedes the earlier simultaneous-start timing and the later second-
request boundary described below. CPU2 begins configuration before CPU1 writes
`7ff2=10` at 8.295870 s, clears the mailbox too early at 8.228872 s, and later
writes result `80` at 13.194725 s. CPU1 remains in `3a18-3a21`, which waits for
an acknowledgement value of zero, so it never consumes that result. The
physical DAT9/mailbox ordering that should align the request write and CPU2
acknowledgement is now the Phase 4 handoff.

The deterministic reconstruction audit is documented in
`firmware/rom-dump-reconstruction.md` and checked by
`tests/rom-boundary-audit.sh`. Phase 3 hardware diagnosis should resume only
from this reconstructed-ROM baseline.

The initial `e789`/`d70b` hypothesis has been tested and rejected as the
immediate path: normal startup performs no post-POST CPU1 access in
`e600-e7ff`, and `d70b/d70f` are not executed. Schematic review established
that E80 belongs to CPU1, not CPU2. Removing CPU2's erroneous private E80
overlay exposed the actual first-request state `e795=00` and a previously
hidden CPU2 low-ROM configuration path.

That path is now complete. E3 page-boundary bytes `14ff=e5`, `30ff=80`, and
`48ff=75` are independently recoverable from raw dump offsets `1400`, `3000`,
and `4800`, consistent with the published Arduino reader's address-port
ordering. Documented DC323 Pause Complete/Scroll Service status semantics are
implemented. CPU2 now writes `7ff2=80` at 12.994345 s and enters E4 at
13.084467 s without a restart or synthetic stack frame.

The next Phase 3 boundary is the second CPU1 graphics test request at
19.380877 s. CPU1 reaches `41f7` with `B=40`, enters the overlapping `3a00`
entry, writes `e795=81`, and submits `7ff2=10` while CPU2 is already in E4.
The immediate next work is to determine what hardware/firmware event should
either prevent this retry or return CPU2 to the low-ROM mailbox service. The
old `e789` work items remain historical hypotheses, not the current priority.

## Why this differs from the original Phase 3 proposal

The planned CPU2 dispatcher audit has already been completed as part of the
earlier investigation:

- E4/E5 bank selection is known.
- The former synthetic continuation stack is removed.
- E4 `12ff=f0` restores the native packet-length store.
- The indirect trampoline and handler return path are traced.
- CPU2 stack and interrupt state remain stable.
- Command 32 reaches its native E4 handler `db98` and then `dc02`.

Phase 3 should begin with a short evidence review of those conclusions, not a
repeat of the audit. Its main work is now the missing startup event.

## Starting evidence

Normal firmware behavior is bounded by two observations:

1. CPU1 reaches `41f7` with `B=40`; `B.6` takes the retry path, so command 32
   is not submitted.
2. When a debugger clears only `B.6`, original CPU1 submits `FF 32 09`. CPU2
   reaches `dc02`, where `7e7e == 7e7f` and no completion event is available.

The closeout experiment proves that producer/consumer inequality at `dc02`
is sufficient for native firmware to reach `dc18` and clear `60bb`.

Static analysis also identifies a high-priority CPU1 path:

```text
d70b/d70f  select PSW.1 state
d711       read XDATA e789
d715       mask with 77
d719       return if zero
d71a       move result to B
d71e       copy PSW.1 to B.3
d721       copy B.6 to carry
d723       clear B.6
d727       write prior B.6 to 7ff4
d72b       jump to 4174, which later reaches 41f7
```

This is the first concrete firmware routine known to prepare a `B.6`-clear
startup state. It is not reached in the failing execution. CPU1 XDATA `e789`
is currently served as ordinary shared RAM, so its hardware identity and the
dispatch mechanism leading to `d70b/d70f` are the first investigation target.

## Working hypotheses, in priority order

1. **Missing decode or status at `e789`.** `e789` is a device/status aperture,
   not ordinary shared RAM, and its missing behavior prevents the `d70b/d70f`
   path or gives that path no event to process.
2. **Missing interrupt or dispatch source.** A real peripheral or timer should
   select `d70b/d70f`, but its interrupt is absent, incorrectly polarized, or
   acknowledged in the wrong order.
3. **One prerequisite drives both gates.** The same event that prepares `B.6`
   may later submit the ring packet awaited at CPU2 `dc02`.
4. **Two sequential prerequisites are missing.** `B.6` selection and the
   post-command-32 ring event may come from different devices.
5. **Scheduler ordering changes an otherwise modeled event.** This remains a
   diagnostic possibility, not a license to extend pulses or queue values at
   firmware PCs.

Keyboard or EEPROM behavior will be investigated only if a traced path links
it to `e789`, `d70b/d70f`, `B.6`, or the expected ring submission.

## Work plan

### 3.0 Confirm the dispatcher closure

- Re-run the existing native command-32 handler trace against the current
  binary.
- Confirm E4/E5 bank transitions, stack pointer, `LCALL`/`RET` path, and first
  arrival at `dc02` match the Phase 2 checkpoint.
- Treat any mismatch as a regression. Otherwise close the original dispatcher
  audit with no further driver change.

**Exit condition:** the current checkpoint reproduces `db98 -> dc02` without
synthetic stack state.

### 3.1 Identify `e789` and its event source

- Inventory every CPU1 read and write in the relevant `e7xx` range, especially
  `e789` and `e7dd`.
- Inspect schematics and address-decode equations for the corresponding CPU1
  aperture and distinguish shared RAM, EEPROM, latch, and peripheral selects.
- Set CPU1 and CPU2 XDATA watchpoints on `e789`, `e7dd`, `7ff4`, and related
  status locations. Record emulation time, processor, PC, data, interrupt
  state, ports, and ring indices.
- Locate all static references or indirect table entries for `d70b` and
  `d70f`. Reconstruct the dispatcher or interrupt source that owns them.
- Record the observed reset value and every writer before the first `41f7`.

**Exit condition:** `e789` has a documented board identity or a narrowly
defined unresolved decode, and the expected predecessor of `d70b/d70f` is
known.

### 3.2 Trace the `B.6` lifecycle

- Capture bounded entries at `38da`, `4174`, `4196`, `4551`, `4587`,
  `d70b/d70f`, `d723`, and `41f7`.
- Record `B`, PSW, stack pointer, interrupt enable, return stack, `7ff4`, and
  the status bytes that feed the selected path.
- Separate initialization values from event-derived values and retry-path
  mutations such as the later `setb B.6` at `4284`.
- If a single status bit is implicated, force that device/status value at its
  actual read—not `B` at `41f7`—and verify that original firmware reaches
  `d723`, then command 32.

**Exit condition:** the expected writer or constructor of the `B` value at
`41f7` is known, with expected and observed inputs documented.

### 3.3 Reconstruct the awaited ring event

- Inventory post-startup call sites for the CPU1 packet constructors and the
  queue writer at `a35a-a387`.
- For each relevant packet, record the producing routine, trigger, byte
  sequence, producer update, and CPU2 handler.
- Trace CPU1 after command 32 is submitted and identify which routine should
  next advance `7e7e` while CPU2 waits at `dc02`.
- Determine whether `4be5` and `7ff7` are alternate completion sources or
  acknowledgements of the same event.
- Use a controlled experiment only after identifying a real packet producer:
  stimulate its input state and require CPU1 itself to write the packet.

**Exit condition:** the expected packet type and its firmware producer are
known, even if the external trigger remains unresolved.

### 3.4 Correlate devices, interrupts, and scheduling

Build one timestamped emulation-time trace containing:

- CPU1 INT0/INT1, internal UART state, T0, and T1.
- CPU2 INT0, DAT9/P1.1, and ROM bank.
- CPU1 P3.5 acknowledgement pulses.
- Reads and writes at `e789`, `e7dd`, `7ff2`, `7ff4`, `7ff7`, and `4be5`.
- Ring producer/consumer changes and command boundaries.
- Entry into `d70b/d70f`, `41f7`, `48f6`, `db98`, `dc02`, and `dc18`.

Repeat the same cold boot with a small scheduler matrix while preserving
physical signal durations. Compare the first state divergence, not final
screenshots alone.

**Exit condition:** scheduling is either ruled out or tied to a specific
missed physical edge/level with polarity and sampling semantics documented.

### 3.5 Implement the verified hardware behavior

- Model the responsible register, interrupt, signal, or device state at the
  board-level decode.
- Remove any diagnostic force used to establish the dependency.
- Do not key the fix to `41f7`, `dc02`, or a success string.
- Add a regression checkpoint at the physical state transition and at the
  corresponding native firmware branch.

**Exit condition:** an ordinary cold boot produces the required CPU1 state and
ring event without debugger intervention.

### 3.6 Acceptance and regression

Run the clean targeted build, ROM verification, Phase 2 closeout regression,
and repeated cold boots. Successful Phase 3 completion requires:

1. CPU1 reaches the command-32 path without clearing `B` in a debugger.
2. CPU1 itself advances the ring event observed by CPU2 at `dc02`.
3. CPU2 reaches `dc18` and clears `60bb` through native firmware.
4. No PC-specific success trigger, injected packet, string rendering, or
   indefinite pulse extension is present in the driver.
5. The first corrected run and repeated cold boots follow the same event path.
6. Any subsequent blocker is reported with an exact PC, state, and bounded
   reproduction rather than hidden by additional forcing.

Reaching the full `VT340 OK` display is the desired outcome, but Phase 3 can
close at the next exact firmware/hardware boundary if the verified completion
event exposes an independent later dependency.

## Instrumentation strategy

- Keep production `VERBOSE` disabled.
- Use bounded Lua debugger scripts and XDATA watchpoints; stop traces as soon
  as the target transition is captured.
- Use MAME emulation time for every event.
- Keep raw `.tr`, `.log`, and screenshots untracked; commit concise summaries
  and reproduction scripts.
- Add driver logging only when it describes a hardware boundary useful beyond
  this single startup path.

## Deliverables

- `phase3-startup-event.md` with the `e789` decode, `B.6` lifecycle, packet
  producer, and corrected control-flow diagram.
- Concise failing and corrected event timelines.
- A table of relevant state variables, all observed writers/readers, expected
  values, and observed values.
- Reproduction scripts for the normal and single controlled hypothesis runs.
- Updated MAME source only for verified hardware behavior.
- Build, smoke, Phase 2 regression, and repeated cold-boot results.
- Updated inventory of synthetic and PC-qualified behavior.

## Stop conditions

Pause and document rather than broaden the scope if:

- `e789` cannot be mapped from available evidence and no firmware predecessor
  can be identified.
- A candidate fix requires inventing a packet or return value with no physical
  source.
- The next blocker is graphics-only and is independent of the startup event.
- New ROM corruption is suspected but cannot be constrained by instruction
  flow and checksum evidence.
