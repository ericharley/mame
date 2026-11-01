# Sprint status: resolve `Wait` to `VT340 OK`

- **Status:** Phase 4 DAT9/mailbox synchronization active
- **Checkpoint:** `acd91b61` (`mame: add VT340 ROM-level emulation checkpoint`)
- **Updated:** 2026-11-01

## Sprint objective

Explain why original DEC firmware remains on the temporary `Wait` display,
identify the firmware/hardware state required for the persistent success
display, and implement only verified hardware behavior. Do not manually draw
`VT340 OK`, inject a success command, or expand unrelated graphics features.

## Executive status

Phase 3 is closed. CPU2 dispatch, ROM banking, stack/return behavior, reset
sequencing, reconstructed ROM execution, and the native low-ROM-to-E4 path are
verified. The MCS-51 core now keeps transmit and receive SBUF directionally
separate, preventing CPU1's POST transmit byte from falsely echoing into its
receive test. See `PHASE3_CLOSEOUT.md` for the complete evidence and exact
Phase 4 handoff.

Phase 4 has now ruled out scheduler quantum, perfect-quantum selection, a
stale retained pulse, immediate DC323 ready latency, and CPU1 timer-0 service
as sufficient causes. The deterministic first failure remains CPU2's `136d`
checkpoint before CPU1 pulse 6 and the later `7ff2=10` pending sentinel. The
active evidence and investigation sequence are in `PHASE4_PLAN.md`.

The first cycle-level interval audit is complete. CPU2's `1325-136d` path is
accounted for as 8.268 ms of native table transfers, T0 synchronization, and
fixed delay loops. After response 5, CPU1's four native SBUF writes and timer
services take 13.579 ms before pulse 6. The resulting 6.898 ms lead of the
CPU2 clear is therefore firmware execution, not lost scheduler time. A full
startup trace also shows no off-by-one rendezvous count.

The schematic and mailbox follow-up close the next two questions. CPU2 P1.1,
CPU1 T1, and DC323 DAT09 are directly connected on `P2 DAT9/TSTATUS H`, so
graphics-table transitions really are visible to CPU1. After POST, CPU2's
`136d` write is the only `7ff2=00`; CPU1 subsequently installs pending
sentinel `10`, waits for zero, and cannot advance to consume CPU2's later
result `80`. CPU2 never reads `7ff2`. The remaining Phase 4
boundary is board timing: shared-memory arbitration, `P3 MC/R H`, and any
CPU2 bus stalls or wait states omitted by the flat shared-RAM model. Although
the schematic shows that CPU1's clock can be gated by MC/R, that behavior
would delay CPU1 and worsen this particular ordering, so it is not itself the
candidate fix.

A controlled build also removed the remaining CPU1 `spin_until_trigger`
handoff at the CPU2 `170e` rendezvous. It produced an identical handshake and
mailbox timeline, so the intervention was restored and ruled out as the
source of the inversion. CPU1 currently accepts response 6 from a CPU2 table
transition that is program-ordered after `136d`; consequently uniform CPU2
slowdown cannot put the sentinel before that write. The next audit must test
shared-RAM write visibility/commit semantics or identify an earlier DAT9 edge
that real CPU1 hardware would consume.

The complete DAT9 transition audit now rules out that earlier-edge branch.
CPU1 polls the live P3.5 level at `3bab/3bbc`; it does not use Timer 1 edge
capture. After response 5 it is inside the native four-byte report delay for
every intervening DAT9 transition, and the last low ends 6.886 ms before CPU1
starts the next wait. Direct pin semantics therefore reproduce the current
behavior.

A debugger-only request-visibility experiment restored the already-issued
zero immediately after CPU1's authentic `7ff2=10` write. Original firmware
then accepted the acknowledgement, consumed CPU2's authentic `80` result, and
continued through `4551`. This establishes mailbox write visibility as the
smallest sufficient boundary but is not a production fix. The next task is to
prove whether E58/shared-RAM arbitration can legitimately inhibit or redirect
that CPU1 write, and to reconstruct why CPU2 starts the operation from DAT9
without reading value `10`. On the schematic-correct I8031 baseline,
the controlled path later encounters the already documented upper-stack issue
before reaching `41f7`.

Recovered PAL dumps now close the shared-write hypothesis. `23-168K5` is E58
and `23-335J5` matches E78. Their decoded equations assert E58 `WDS L` and E78
DRAM `MWR L` for CPU1's observed external write state, so the real E93/E94
pair must store `7ff2=10`. The debugger visibility experiment is therefore a
dependency proof only, not plausible hardware behavior. Phase 4 returns to
the pre-ack DC323 table interval: determine whether command latency or an
external DAT9 ownership interval lets CPU1 complete pulse/response 6 before
CPU2 executes `136d`.

That DC323 follow-up is now bounded as well. The two `17cf` groups contain 18
I/D commands each (36 total), normally spaced 24 microseconds apart, and each
group lasts 2.383 milliseconds. This already exceeds the documented minimum
command spacing by about eight times, so ordinary missing-ready latency cannot
add the required 6.9 milliseconds. The third recovered PAL, `23-336J5`, is
E16—the output-map/palette decoder—not a DC323 or DAT9 ownership PAL. E78
directly generates the DC323 `P3 DS L` select, and E16 has no DAT9 connection.
The next Phase 4 branch is therefore ROM/board revision consistency and the
exact CPU2 configuration-table selection, not another scheduler or PAL delay.

The first ROM-consistency check supports the executed path. The independent
9track `23-236E6` E49 image exactly matches the Avitech E49 dump. On the
critical code path, E3 `30ff=80` is the coherent `SJMP 3119`, and E4's table
boundary uses raw `6000=3a` to form command/value record `3a 38 88`; the naive
rotated value `c5` would corrupt the table. No remaining page-boundary repair
currently explains the extra table work. The next audit is the contract
between CPU1's four fixed-delay `3ac9/3b64` SBUF writes and CPU2's rendezvous
sequence.

A controlled debugger experiment now proves that contract is the immediate
dependency. Shortening only the two inner delay loops for the four-byte report
after response 5 moves pulse 6 into CPU2's still-active table transfer. Native
CPU1 then posts `7ff2=10` at 8.222455 s, native CPU2 clears it at 8.228779 s,
and CPU1 consumes the authentic zero and later result `80`. This is diagnostic
evidence only: TMOD=`21`, TH1=`f3`, PCON=`ff` establishes approximately
4800-baud UART pacing, so the fixed report delay is intentional and remains
unchanged in production. See `traces/phase4-report-delay-summary.txt`.

The firmware provenance is also resolved more precisely. Archive photographs
show that all five dumps came from one cartridge labeled `VT330/340 V1.1`,
and E5 contains localized V1.1 version text. DEC field-change order
VT330-I001 replaced this cartridge with V2.1 because multiple V1.1 bugs were
corrected. The order does not name the current startup timing, so this is not
yet a causal claim. No public V2.1 dump has been found; acquiring V2.1 or its
`EK-VT3XX-RN-003` release notes is now the highest-value comparison before a
production timing change is considered.

The fallback table-duration experiment is complete. Repeating CPU2's
authentic first `17cf` group four extra times (+9.540 ms) is insufficient;
CPU1 still obtains response 6 only after `136d`. Five extra groups
(+11.925 ms) are sufficient because pulse 6 then overlaps the native second
group, allowing pending sentinel `10` to precede CPU2's unchanged zero. This bounds the
dependency but strongly rejects ordinary DC323-ready latency or a generic CPU
stall: success requires continued DAT9 table transitions and five unrequested
18-command groups. Nothing from this experiment is enabled in production.

The complete `7ff2` cross-reference now corrects the protocol terminology.
CPU2 has no read of `7ff2`; CPU1's `10` is therefore a pending sentinel, not a
request. CPU2 publishes checkpoint zero at `136d`, success `80` at `163e`, or
an error result through writers at `159f`, `197a`, and `1b24`. CPU1 first waits
for zero at `3a18`, then for a nonzero final result at `3a31`. The failure is
precisely that CPU1 overwrites the already-published checkpoint with `10` and
waits for a second zero that never occurs. See
`traces/phase4-mailbox-semantics-summary.txt`.

The launch path is now explicit as well. CPU1 pulse 5 releases CPU2's sixth
`1701` rendezvous, after which CPU2 reads `e795=00` and starts the test. CPU1
does not write its computed `e795=01` until immediately before the much later
pending-sentinel write. Forcing that later value at CPU2's exact decision
point moves checkpoint zero 0.348 ms earlier and result `80` about 4.43 s
earlier, worsening the failure. This rules out stale `e795` configuration as
the missing synchronization and confirms DAT9—not `7ff2`—launches CPU2.
Schematic page 18 also identifies P1.6 as the firmware-driven `CPMRESET H`
output, so the computed value is not sourced from a missing external strap.

The V2.1 search has reached the limit of current public artifacts. DECnotes
retains metadata for two directly relevant V1.1/V2.1 discussions, but its
downloadable archive has no note-body file for that conference. Public ROM
inventories have no V2.1 E1-E5 set. Details and immediate comparison targets
are recorded in `firmware/v21-search.md`; further progress on that branch
requires a new physical dump or archival source.

The same archive supplies the previously missing 512-byte `23-001N2` E80
image. It contains structured setup data rather than an erased pattern. A
live-P1 trace found no CPU1 external access while NVREN was low before the
current mailbox boundary, so E80 does not directly cause the first inversion.
Its E10-latched chip-select/read/write interface still needs reconstruction
before the image can be connected for later-startup testing.

The ROM baseline has been corrected more broadly than the earlier isolated
repairs. The published Arduino dump corrupts every page transition; all 630
recoverable E1-E5 page-final positions are now reconstructed from their raw
`xx00` samples, changing 613 byte values. The firmware checksums rebuild the
uncaptured tails as E1 `8e`, E2 `77`, E3 `62`, E4 `eb`, and E5 `6e`.

This restores E1 `38ff=78`, the code that clears CPU1 P1.0 and releases CPU2's
active-high reset, plus CPU1 `3aff`, which returns the successful POST path
instead of entering the error reporter. The driver now models the schematic
reset connection. CPU2 is released at 0.558338 s and the native DAT9 handshake
succeeds at 0.573882 s. CPU2 currently clears `7ff2` at 8.228779 s, before CPU1
writes pending `10` at 8.295773 s, then writes result `80` at 13.194725 s.
CPU1's `3a18` loop waits for zero, so it cannot consume the result. This
DAT9/mailbox ordering is the current blocker. Older 13-19 s timings below
describe the pre-audit, simultaneous-CPU baseline and are retained only as
investigation history.

The investigation has moved the blocker out of the renderer and into a
specific startup-control sequence. Both CPUs boot, the native command
dispatcher works without its former synthetic stack frame, and original
graphics operations render `Wait` correctly.

Phase 3 corrected the schematic ownership of E80, exposed the CPU2 path used
when shared `e795=00`, and completed that path. Three newly reached E3 page-
boundary dump defects are reconstructed at logical `14ff`, `30ff`, and
`48ff`. The first two are on the normal path: CPU2 now completes its eight-
frame DC323/DC7051 configuration tests, writes authentic success `7ff2=80` at
12.994345 s, and enters operational E4 firmware at 13.084467 s. DC323 status
bits 0/1 now use the documented sticky, write-zero-to-clear frame semantics.

Before the full ROM reconstruction, normal execution reached CPU1 `41f7` with
`B=40` and took a second graphics retry/test path rather than submitting
command 32. That Phase 2 observation remains valid control-flow evidence, but
it is no longer the first failing boundary in the corrected cold boot.

At that wait, producer `7e7e` equals consumer `7e7f`. A bounded closeout
experiment exposes one sentinel ring slot and proves that native `bc9d` then
sets carry, branches to `dc18`, and clears `60bb` at `dc1c`. The experiment
terminates at `dc1d`, before the sentinel can be interpreted as a command.

The production driver still displays `Wait`, as it should until the current
DAT9/mailbox ordering defect is identified and modeled.

## Completed work

### Phase 0: deterministic baseline

- Recorded three byte-identical 20-second cold-boot event logs.
- Recorded three byte-identical screenshots.
- Established stable firmware timings for POST report, `Wait`, command-ring
  consumption, and final equal producer/consumer indices.

### Phase 1: native CPU2 dispatcher

- Removed the synthetic CPU2 continuation-stack intervention.
- Reconstructed E4 logical byte `12ff=f0`, restoring the native packet-length
  store at CPU2 `92ff`.
- Verified indirect handler dispatch, normal handler return, enabled
  interrupts, stable stack state, and complete ring consumption.

### Phase 2: controlling state and backward trace

- Identified CPU2 `1796-17b2` as the unconditional `Wait` request and latch set.
- Identified CPU1 `41f7` and observed `B=40` as the first normal-path decision
  preventing command 32.
- Reconstructed three additional dump defects found through impossible native
  control flow:

  | ROM location | Repair | Effect |
  |---|---:|---|
  | E2 `3bff` | `1f` | Restores the valid `be1f` table helper and removes recursive stack growth |
  | E4 `622d` | `02` | Restores command-21 packet length and preserves later packet framing |
  | E5 `72ff` | `09` | Terminates the intended eight-entry bit-mask loop |

- Proved that clearing only `B.6` produces original firmware command 32.
- Traced CPU2 command 32 through handler `db98` to the exact `dc02` wait.
- Proved with a bounded ring experiment that producer/consumer inequality is
  sufficient to reach `dc18` and clear `60bb`.
- Added deterministic normal-path and controlled-path regression scripts.
- Updated the open-hardware record and timestamped event summary.
- Preserved all forcing in debugger scripts; none is present in the driver.

### Phase 3: CPU2 dispatcher, low-ROM, and execution-integrity audit (complete)

- Verified from the schematic that E80 is owned by CPU1, and removed the
  incorrect CPU2 `e600-e7ff` private EEPROM overlay.
- Corrected CPU1 P1 readback: P1.4 is `NVREN`, while P1.5 is
  `MFGTEST/STATUS`; neither is replaced by the driver's POST arbitration flag.
- Identified the dump mechanism's page-crossing artifact from the published
  Arduino reader and recovered authentic boundary values from earlier raw
  page slots.
- Reconstructed E3 `14ff=e5`, `30ff=80`, and `48ff=75`; updated the checksum
  tail to `55`.
- Implemented documented DC323 Pause Complete and Scroll Service sticky
  status, interrupt enable, and write-zero-to-clear acknowledgement behavior.
- Verified native CPU2 success at `1639` and the operational jump at `16ef`.
- Corrected the MCS-51 SBUF transmit/receive latch separation, preserving
  CPU1 `B=40` through its POST serial test.
- Added `tests/phase3-checkpoint.sh`, which proves the repaired low-ROM path
  and fails on a second POST entry or the old `3106` dead loop.

## Current state variables

| State | Normal observed value | Required transition | Known writer/reader |
|---|---:|---|---|
| CPU1 receive SBUF after transmit | `00` | Remain independent of transmit `55` | MCS-51 RX/TX latches; read at CPU1 `3906` |
| CPU1 `B` after serial POST | `40` | Remain `40` | initialized at `38e6`; checked at `390e` |
| CPU2 `7ff2` checkpoint | `00` at 8.228779 s | Occur after CPU1 installs sentinel | CPU2 `136d`; CPU1 reads at `3a18` |
| CPU1 `7ff2` pending sentinel | `10` at 8.295773 s | Precede checkpoint | CPU1 `3a0d`; CPU2 never reads it |
| CPU2 `7ff2` result | `80` at 13.194725 s | Be consumed after checkpoint | CPU2 `163e`; CPU1 reads at `3a31`/`3a3a` |
| DAT9 response | low/high at 8.228786-8.228791 s | Align CPU1 response wait with the transaction | CPU2 P1.1; CPU1 handshake code |

## Acceptance status

| Criterion | Status |
|---|---|
| Original firmware leaves `Wait` in normal configuration | Not yet |
| Original ROM submits the `VT340 OK` drawing commands | Not yet |
| Renderer accepts firmware operations without a banner-specific change | Yes |
| Transition is tied to documented firmware state | Partially: both gates are identified |
| No hardcoded string, success PC trigger, or synthetic production packet | Yes |
| Repeated cold boots are stable | Yes |
| Persistent success state is reached | Not yet |

Phase 3 closed with an exact next boundary and a bounded experiment. The
overall sprint remains open in Phase 4 synchronization work.

## Verification

- Targeted MAME build completes without compiler errors.
- `tests/smoke.sh` passes `-listfull`, `-verifyroms`, and a short boot.
- `tests/phase2-closeout.sh` verifies:
  - `Wait` latch reaches `01` in normal execution.
  - CPU1 reaches `41f7` with `B.6` set.
  - command 32 remains absent in the normal bounded run.
  - the driver contains no Phase 2 decision-point forcing.
- The archived Phase 2 ring trace records the bounded diagnostic transition
  through `dc18/dc1d`; Phase 3's corrected earlier startup path no longer uses
  that forced experiment as a regression gate.
- Three independent 15-second unthrottled cold boots complete normally.
- `tests/phase3-checkpoint.sh` passes the smoke test and verifies exactly one
  reset entry, separate UART latches, `30f9 -> 3119`, continuation across
  `14ff`, `7ff2=80`, and entry to operational E4 firmware.
- `tests/rom-boundary-audit.sh` verifies all recoverable page-final bytes and
  the reconstructed checksum tails for E1-E5.
- MAME reports only the expected `e80.bin` `NO_DUMP` warning.

Run the closeout regression from the MAME root with:

```sh
vt340-research/tests/phase2-closeout.sh ./vt340
```

## Remaining risks and synthetic behavior

- DAT9 response sampling and the `7ff2` sentinel/checkpoint order do not
  yet match the physical protocol.
- CPU1 perfect-quantum scheduling, the 10 microsecond maximum-quantum
  override, and the sentinel-adjacent retained DAT9/T1 pulse have been removed;
  none changed the Phase 4 event sequence.
- CPU1 now uses the schematic-correct I8031 core. The former I8032 storage
  workaround has been removed; the current Phase 4 timeline is unchanged.
  A previously observed later serial-service stack excursion above `7f`
  remains a risk after the startup blocker is resolved.
- DAT9/T1 pulses are retained at known rendezvous to cross scheduler slices.
- The LK201 power-on reply is synthetic.
- E80 contents are undumped and its CPU1 bus interface is not yet modeled.
- Some video POST/status behavior is still PC-qualified.
- Incomplete raster modes and palette behavior remain, but current evidence
  rules them out as the cause of this startup transition.

## Recommended next work

Continue Phase 4 from the stable timeline in `PHASE4_PLAN.md`. Locate a V2.1
cartridge dump or `EK-VT3XX-RN-003`, then compare CPU1 `3ac9/3b64`, CPU2's
six `1701` rendezvous, and CPU2 `1325-136d` with the matched V1.1 firmware.
The report-delay experiment is a dependency proof only. Do not shorten it,
repeat table groups, add a PC-qualified checkpoint, or force a mailbox
value in the normal configuration.

## Key references

- `PROJECT_SUMMARY.md`: architecture and engineering approach.
- `firmware/wait-to-ok.md`: firmware analysis through the Phase 3 boundary.
- `firmware/v21-search.md`: V2.1 provenance search and comparison targets.
- `PHASE3_CLOSEOUT.md`: Phase 3 evidence and exact Phase 4 handoff.
- `traces/wait-to-ok/phase2-event-summary.txt`: concise timestamped paths.
- `hardware/unknowns.md`: unresolved and provisional hardware behavior.
- `hardware/video-hardware.md`: implemented raster and scanout model.
- `BUILDING.md`: build and debugger procedure.
