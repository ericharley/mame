# Open hardware questions

## CPU2 upper indirect-data accesses - resolved

- Evidence: both installed parts are documented as 8031C; Intel specifies
  128 bytes of RAM for 8031 and 256 for 8032.
- Finding: the upper-IDATA writes occurred only when the driver selected E4
  at reset.  Correct reset selection of E5 eliminates them and reaches a
  coherent DC7051 status poll.  They were a wrong-bank artifact, not evidence
  for an 8032.
- Decision: keep MAME's I8031 core.  See
  `../firmware/internal-ram-investigation.md`.
- Status: resolved; no CPU substitution or fabricated RAM.

## External data maps - partially resolved

- Evidence: schematic shows RAM, latches, serial paths, and board arbitration.
- Hypothesis: both CPUs see partially decoded register/RAM windows.
- Finding: CPU2 first blocks at mirrored DC323 register 3, waiting for ready status.
  The `f?00-f?3f` block is a 16-bit register window: CPU2 P1 carries bits
  15-8 and MOVX carries bits 7-0.  Writes to registers 20, 21, 2a, and 2b are
  now retained rather than falling through to shared RAM.
- Resolution: DEC's Dragon specification identifies the register block and
  its ready bits; the first normal rasterops now use the retained registers.
- Status: resolved for POST and the first E49 text path; generic commands remain.

## CPU1 formatter trap and stack growth

- Evidence: an instruction trace shows `LCALL 09e4`; when B.0 is clear,
  `JNB B.0,098a` enters an overlapping path that recursively pushes state.
  The direct read at `098b` is literally `XRL A,C2`; it is not an external
  register access.
- Experiment: substituting the I8032 core removes upper-IDATA warnings but
  leaves the same 63,964 C2 reads in one second and does not escape the loop.
- Resolution: the target's unimplemented SFR behavior is modeled as `c2=ff`.
  CPU1 escapes the path and reaches its `7ff1` interprocessor completion wait.
- Status: resolved without changing the documented I8031 core.

## CPU1 normal serial-service upper IDATA

- This is distinct from the earlier `09e4` formatter trap.  After POST and
  normal initialization, the timer-driven service routine at `56eb` enters
  the `bb11` serial poller.  With working SCN2681 status transitions it makes
  thirteen nested polls, grows SP from `58` through upper indirect RAM to
  approximately `8c`, then unwinds normally and returns to SP `4d`.
- MAME's I8031 core treats `80-ff` as unmapped; execution corrupts before the
  serial event arrives.  I8032 storage behavior completes the same ROM path,
  keeps both CPUs stable, and exposes the first persistent visible pixel.
- Contradiction: schematic page 18 and the parts list explicitly identify E57
  as an 8031.  No Timer 2 behavior is required or used; only the 256-byte RAM
  organization is currently needed.
- Current decision: use the schematic-correct I8031 core. Removing the I8032
  storage substitution leaves the current startup path and Phase 2/3/4
  checkpoints unchanged because CPU1 is still blocked before the later
  serial-service condition becomes decisive. The upper-stack observation
  remains an unresolved risk once startup progresses.

## Initial DAT9 response phasing - unresolved

- The reset-relative trace places CPU2's first `1701` DAT9 low at 6.478 ms,
  release at 6.981 ms, and CPU1's first `3922` low-response sample at
  15.534 ms: an 8.553 ms gap.
- Removing the retained startup event makes CPU1 time out at `3933`; explicit
  DAT9 resolution and timeslice handoff do not change the physical high level
  during that wait.
- CPU2 reaches the pulse through fixed initialization: explicit DC323 reset
  delays, a 23-register table load, and a 4.31 ms internal-RAM test. There is
  no firmware-visible ready poll in this path.
- Schematic sheets 1-3 show CPU1 P1.0 connected directly to CPU2 RST and CPU2
  receiving the ungated 12 MHz CPUBCLK. There is no shown reset-delay circuit
  or slower CPU2 clock that could provide the missing interval.
- The compatibility retention at CPU1 `3925` remains, but is now identified as
  masking a startup phase/timing mismatch rather than a scheduler-slice loss.
  The opposite CPU1-to-CPU2 retention at `1711` proved redundant and is gone.
- This does not directly reverse the later `7ff2` race because intervening
  `1701` calls resynchronize the processors. It is evidence that an earlier
  reset, clock, or bus-phase assumption still needs hardware justification.
- See `../traces/phase4-initial-pulse-retention-summary.txt`.

## CPU2 graphics initialization and command-ring handoff - resolved for current path

- Evidence: CPU1 posts `ff` at shared RAM `7ff1` and polls until CPU2 changes
  it.  CPU2 ROM contains the matching clear operations at E3 `0f27`/`0f3c`.
- Finding: corrected status, timing, and POST behavior lets CPU2 acknowledge
  the mailbox, complete graphics initialization, and enter the E4 normal loop.
- Schematic: E70 DC323 drives CPU2 active-low INT0 as `P10 INTRREQ L`; the
  DC7051 timing and DC323 status are modeled to the observed firmware paths.
- Rejected diagnostics: a one-shot INT0 request is ignored while `IE=00`; a
  late CPU2 reset and all-ones reads in a candidate aperture do not clear the
  mailbox.
- New finding: `7e7e` and `7e7f` are producer and consumer indices, not
  mismatched copies.  The E4 decoder consumes variable-length packets, stores
  a handler pointer in `60ab/60ac`, and must store its length in `60ad`.
- Resolution: dumped E4 byte `12ff` (`92ff` in CPU space) was corrupt.  The
  dumped `22` (`RET`) returned through an empty stack; the surrounding routine
  proves it is `f0` (`MOVX @DPTR,A`).  Repairing it restores the length store,
  fall-through to `9300`, the `9327` indirect call, and normal handler return.
  The former synthetic continuation frame has been removed.
- Status: command processing is stable; completing the startup drawing path is
  the current visible-boot blocker.

## Successful power-up banner - resolved; fast-path latency remains

- Evidence: CPU2 writes `7ff2=80` from E3 `163c-163e`, proving its own POST
  success. CPU2 then draws `Wait` and sets `60bb=01`.
- Finding: CPU1's steady command stream is byte-exact and finite
  (`2c`, `24`, `0c`, `06`, `07`, `08`, `14`, `16`, `17` packets). CPU2 maps
  each packet to a valid E4 handler, and all resulting rasterops are executed.
- Rejected explanations: the banner is not hidden in the off-screen E49
  initialization grid, is not waiting behind a PBT command, and is not exposed
  by the final DC323 offset/index/scroll state (all are zero).
- Historical Phase 2 lead: CPU1 reached `41f7` with `B=40`, so `B.6` prevented
  command 32. Clearing only that decision bit made original firmware submit
  command 32; CPU2 executed its repaired handler through `dc02`, where it
  waited because ring producer `7e7e` equaled consumer `7e7f`.
- Controlled result: making one debugger-only ring slot visible at `dc02`
  takes the native carry branch to `dc18` and clears `60bb` at `dc1c`.
- Historical Phase 4 boundary: after full ROM reconstruction and correction of
  the MCS-51 SBUF latches, CPU2 writes the `7ff2=00` checkpoint before CPU1
  installs stale-zero guard `10`. CPU1 consequently overwrites the only zero
  checkpoint and loses the fast path. Its bounded wait expires at 119.955290 s
  and it consumes CPU2's authentic `80`, entering startup routine `4551` at
  119.995547 s. CPU1 then enqueues 23 startup packets and waits in `f2a7`,
  while the former PC-qualified DC323 bit-0 inversion caused immediate INT0
  re-entry and left the ring consumer at `00`. Removing that inversion lets
  CPU2 acknowledge Pause Complete with `fe`, Scroll Service with `fd`, and
  drain all 102 startup packets natively. CPU1 reaches command 32 and CPU2
  reaches `dc02` with producer and consumer both `66`. The next boundary is
  the later completion event needed to take `dc18` and clear `60bb`.
  CPU2 has no read of `7ff2`, so that location is not a request/acknowledgement
  mailbox. See `traces/phase4-post-timeout-report.md`.
- Resolution: E80 EEPROM behavior, both SCN2681 local-loopback channels, and
  SCN2641 local loopback now pass. CPU1 submits result `00`; command 32 and the
  E49 PBT path produce the original `VT340 OK` records. Frame-boundary erase
  removes `Wait`, and the panel remains visible.
- Remaining issue: this success still follows the firmware timeout at
  119.955290 seconds because CPU1 misses the earlier `7ff2=00` checkpoint.
  Banner generation is resolved; fast-path startup synchronization is not.

## CPU2 ROM bank polarity for the dumped cartridge - resolved

- Evidence: E4/E5 chip enables and page-20 equations are known.
- Finding: the actual ROMBANK1 signal is P3.3; high selects E4 and low selects
  E5.  This mapping completes POST and reaches the E4 operational loop.
- Status: resolved by controlled firmware execution.  Alternate cartridge
  strap configurations remain untested.

## E80 initial state and persistence - resolved

- Evidence: the schematic identifies E80 as an X2804AP-45. The archived DEC
  `23-001N2` image is independently catalogued as VT340 location E80 and is
  exactly 512 bytes. Its SHA-256 is
  `1470ab44a5412341d384cb917e13b9ae1ba209b8b61041b2c5ad57d998cc55a8`.
- Finding: the payload contains structured setup data and is not erased.
- Trace result: no CPU1 external access occurs while live P1.4/NVREN is low
  before the current 13.2-second mailbox boundary. E80 therefore does not
  directly explain the first acknowledgement inversion.
- Late-startup finding: routines `3c27` and `3d5a` clock E10 at `4156` and
  read E80 through `f000-f1ff` while P1.3/NVRDS is low. The recovered image
  makes every native seeded checksum equal zero and clears POST result bit 0.
- Write-path finding: firmware routine `3da9` selects E80, compares the old
  byte, writes only changed data, and executes its native programming delay.
  MAME's X2804 device now receives those writes and persists its 512-byte
  contents through the standard NVRAM interface.
- Regression result: changing Global On-Line/Local to `local`, invoking Save
  Current Settings, and cold booting with the same NVRAM directory restores
  both the current and saved value as `local`.
- Status: resolved; see `tests/nvram-persistence.sh`.
