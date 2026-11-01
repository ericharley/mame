# Phase 3 closeout: CPU2 dispatcher and startup execution integrity

## Status

Phase 3 is complete. Native CPU2 dispatch, bank selection, stack/return
behavior, reset entry, ROM execution, and the low-ROM-to-E4 transition are now
verified without a synthetic continuation frame.

The remaining startup failure is not a dispatcher defect. It is the Phase 4
DAT9/shared-mailbox synchronization issue described below.

## Corrections established during Phase 3

- Removed the synthetic CPU2 continuation-stack intervention.
- Restored the native E4 dispatcher stream and packet framing.
- Generalized the Arduino dump reconstruction across all five processor ROMs,
  restoring 630 recoverable page-final positions and rebuilding all checksum
  tails.
- Corrected E80 ownership and removed CPU2's false EEPROM overlay.
- Modeled CPU1 P1.0 as CPU2's schematic active-high reset input.
- Implemented documented DC323 sticky status/interrupt acknowledgement.
- Corrected the MCS-51 core's SBUF direction semantics: a transmit write no
  longer overwrites the independent receive latch.

The SBUF correction is essential native behavior. CPU1 transmits `55` during
POST and expects a disconnected receive path not to echo it. The old core read
back the transmit byte, set `B=bf`, and selected an error path. The corrected
core reads receive SBUF `00`, preserves `B=40`, and continues normally.

## Verified execution

- CPU1 asserts CPU2 reset at cold boot and releases it at `390e`.
- The DAT9 rendezvous reaches CPU1 `3952` successfully.
- CPU2 executes the reconstructed E3 configuration path, including
  `30f9 -> 3119` and `14fc -> 1501`.
- CPU2 writes authentic result `7ff2=80` at `1639`.
- CPU2 enters operational E4 through `16ef`.
- No second reset-vector entry, old `3106` dead loop, synthetic stack frame,
  hardcoded display command, or command injection is present.

`tests/phase3-checkpoint.sh` now asserts the separate UART latches as well as
the native low-ROM path. `tests/rom-boundary-audit.sh` independently checks
all recovered boundary anchors and checksum tails.

## Exact Phase 4 handoff

The remaining first divergence is ordering on DAT9 and shared byte `7ff2`:

| Emulated time | Event |
|---:|---|
| 8.220495 s | CPU2 begins configuration after the fifth DAT9 rendezvous |
| 8.228776 s | CPU2 publishes checkpoint `7ff2=00` at `136d` |
| 8.228786-8.228791 s | CPU2 drives its explicit DAT9 low/high response |
| 8.235659 s | CPU1 emits its sixth DAT9 pulse |
| 8.295748 s | CPU1 finally observes a later P1.1 transition and completes the response wait |
| 8.295771 s | CPU1 installs pending sentinel `7ff2=10` |
| 13.194725 s | CPU2 writes result `7ff2=80` |

CPU1 loop `3a18-3a21` requires an observed zero after installing `10`. Because
CPU2's only normal zero write occurred earlier, CPU1 ignores the later `80`.
CPU2 has no read of `7ff2`; the Phase 4 cross-reference therefore identifies
`10` as a pending sentinel rather than a request.

A bounded diagnostic read substitution presents zero at `3a19` only when the
authentic `80` arrives. CPU1 then exits the checkpoint loop at
13.194739 s and consumes the untouched `80` at `3a3a` at 14.582721 s. This
proves the controlling condition and preserves original firmware result
handling; it is not enabled in normal configuration.

The next phase must determine why the physical DAT9/table-transfer sequence
places CPU1's sixth pulse and sentinel before CPU2's `136d` checkpoint.
Candidate scope is scheduler ordering, P1.1 open-collector sampling, and
graphics-bus/status timing. A delayed PC-triggered checkpoint or a
permanent forced mailbox value is not an acceptable fix.
