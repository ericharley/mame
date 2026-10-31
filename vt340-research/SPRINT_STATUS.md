# Sprint status: resolve `Wait` to `VT340 OK`

- **Status:** Phase 2 closed; startup transition isolated but not resolved
- **Checkpoint:** `acd91b61` (`mame: add VT340 ROM-level emulation checkpoint`)
- **Updated:** 2026-10-31

## Sprint objective

Explain why original DEC firmware remains on the temporary `Wait` display,
identify the firmware/hardware state required for the persistent success
display, and implement only verified hardware behavior. Do not manually draw
`VT340 OK`, inject a success command, or expand unrelated graphics features.

## Executive status

The investigation has moved the blocker out of the renderer and into a
specific startup-control sequence. Both CPUs boot, CPU2 reports POST success,
the native command dispatcher works without its former synthetic stack frame,
and original graphics operations render `Wait` correctly.

Normal execution stops progressing because CPU1 tests `B.6` at `41f7` with
`B=40`. It therefore takes the retry path and never submits command 32. A
debugger-only clear of `B.6` proves that original CPU1 firmware then submits
`FF 32 09`. CPU2 natively dispatches this to E4 handler `db98`, completes its
E4/E5 setup, and reaches `dc02`, where it waits for another command-ring event.

At that wait, producer `7e7e` equals consumer `7e7f`. A bounded closeout
experiment exposes one sentinel ring slot and proves that native `bc9d` then
sets carry, branches to `dc18`, and clears `60bb` at `dc1c`. The experiment
terminates at `dc1d`, before the sentinel can be interpreted as a command.

This establishes the control dependency but not the real event source. The
production driver still displays `Wait`, as it should until that source is
identified and modeled.

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

## Current state variables

| State | Normal observed value | Required transition | Known writer/reader |
|---|---:|---|---|
| CPU1 `B.6` at `41f7` | `1` (`B=40`) | Clear to enter command-32 path | initialized at `38e6`; read at `41f7` |
| CPU2 `60bb` | `01` | Clear after command-32 completion | set at `17b2`; cleared at `dc1c` |
| Ring producer `7e7e` | equals consumer | Advance for a new event | CPU1 `a383`; read by CPU2 `bca3` |
| Ring consumer `7e7f` | equals producer | Remains behind producer at `dc02` | CPU2 `bcd1`; read by CPU2 `bca7` |
| CPU2 `4be5` | `00` | Source semantics not yet resolved | read by `dc0f-dc15` |
| CPU2 `7ff7` | repeatedly `00` | Completion semantics not yet resolved | cleared by `dc0b` |

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

The sprint therefore closes with the plan's permitted unresolved deliverable:
an exact decision point, expected state, observed state, and smallest
reproducible experiment.

## Verification

- Targeted MAME build completes without compiler errors.
- `tests/smoke.sh` passes `-listfull`, `-verifyroms`, and a short boot.
- `tests/phase2-closeout.sh` verifies:
  - `Wait` latch reaches `01` in normal execution.
  - CPU1 reaches `41f7` with `B.6` set.
  - command 32 remains absent in the normal bounded run.
  - the driver contains no Phase 2 decision-point forcing.
  - the controlled ring transition reaches `dc18` with `60bb=01`.
  - original firmware reaches `dc1d` with `60bb=00`.
- Three independent 15-second unthrottled cold boots complete normally.
- MAME reports only the expected `e80.bin` `NO_DUMP` warning.

Run the closeout regression from the MAME root with:

```sh
vt340-research/tests/phase2-closeout.sh ./vt340
```

## Remaining risks and synthetic behavior

- The real source of the `B.6` clear and later ring event is unknown.
- The two conditions may be different observations of one missing startup
  prerequisite, or they may be sequential dependencies.
- CPU1 currently uses I8032 RAM organization despite the documented 8031.
- DAT9/T1 pulses are retained at known rendezvous to cross scheduler slices.
- The LK201 power-on reply is synthetic.
- E80 contents are undumped and modeled erased.
- Some video POST/status behavior is still PC-qualified.
- Incomplete raster modes and palette behavior remain, but current evidence
  rules them out as the cause of this startup transition.

## Recommended next work

The detailed execution plan is in `PHASE3_PLAN.md`.

The originally planned dispatcher audit is substantially complete: bank
selection, stack behavior, indirect dispatch, returns, and the former
synthetic continuation have all been resolved. The next productive round
should focus on the source of the missing CPU1 event rather than repeat that
audit.

1. Enumerate CPU1 call sites that submit through `a383` after startup and map
   each packet type to its prerequisite.
2. Trace all paths capable of clearing or replacing `B.6` before `41f7`,
   including the state saved/restored by `4551-4587`.
3. Correlate those paths with keyboard completion, serial-controller status,
   EEPROM/configuration validity, timers, and CPU2 acknowledgements.
4. Record a single emulation-time timeline containing CPU1/CPU2 interrupts,
   DAT9/T1, `7ff2`, `7ff7`, `4be5`, and ring producer/consumer transitions.
5. Vary scheduler quantum only to detect the first divergence; do not lengthen
   pulses or queue status values for specific PCs as a fix.
6. Once a direct dependency is proven, model the physical device or signal
   that produces it and rerun the normal cold-boot acceptance tests.

Do not add new graphics features, keyboard interaction, or peripheral devices
unless a traced dependency from `41f7` or `dc02` requires them.

## Key references

- `PROJECT_SUMMARY.md`: architecture and engineering approach.
- `firmware/wait-to-ok.md`: complete Phase 0-2 firmware analysis.
- `traces/wait-to-ok/phase2-event-summary.txt`: concise timestamped paths.
- `hardware/unknowns.md`: unresolved and provisional hardware behavior.
- `hardware/video-hardware.md`: implemented raster and scanout model.
- `BUILDING.md`: build and debugger procedure.
