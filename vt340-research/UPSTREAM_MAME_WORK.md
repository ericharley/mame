# Potential upstream MAME device and CPU-core work

## Purpose

This document separates reusable MAME device/core corrections discovered by
the VT340 work from the VT340 driver itself.  Each item should be revisited as
an independent, minimal upstream change with its own hardware justification,
focused regression coverage, and reviewable commit.

The existing commits are provenance, not proposed upstream commits.  They mix
shared-device changes with substantial VT340 work and should not be submitted
as-is:

- `beb58c4b` contains the MCS-51 SBUF correction.
- `24768cb9` contains the generic serial parity correction and three logically
  separate SCN2641/PCI-family corrections.

## Ground rules for the later upstream effort

1. Split patches by independently explainable behavior.  Do not combine a
   generic serial fix, an SCN2641 fix, and VT340 driver wiring in one change.
2. Demonstrate the pre-fix failure and post-fix result with a small test that
   exercises the shared device directly where practical.  Use the VT340 POST
   as integration evidence, not as the only test.
3. Cite the relevant component specification and describe the emulated state
   transition, not merely the application that benefits.
4. Audit other users of the affected device and run an appropriate build and
   smoke-test set before submission.
5. Avoid firmware-address checks, forced status values, artificial timing,
   and application-specific expected bytes in shared devices.
6. Keep uncertain behavior out of a patch until the hardware contract is
   established.  A narrow proposal or RFC is preferable to a speculative API.

## Backlog summary

| Priority | Component | Candidate change | Current confidence | Recommended upstream unit |
| ---: | --- | --- | --- | --- |
| 1 | `device_serial_interface` | Calculate parity from the configured data width | High; verified root cause and correction | Standalone fix plus focused framing test |
| 2 | MCS-51 core | Keep the SBUF receive and transmit latches logically separate | High; matches the CPU architecture and fixes a native diagnostic | Standalone core fix plus UART-register test |
| 3 | SCN PCI/ACI family | Do not latch the reset-error command bit | High; direct implementation error | Standalone command-register fix |
| 4 | SCN2641 | Keep MR1 and MR2 independent on ACI devices | High for SCN2641; verify against all affected variants | Standalone ACI-specific fix |
| 5 | SCN2641 | Keep the async-only device idle while its mode field is invalid after reset | Medium-high; corrects a verified bad initial state | Separate ACI reset/state-machine fix |
| 6 | MCS-51 core | Expose external MOVX bus strobes or an equivalent bus-cycle phase | Design proposal; behavior needed, API not yet established | RFC/design first, implementation separately |

## 1. Configured-width parity in `device_serial_interface`

### Problem

`device_serial_interface::transmit_register_setup` serializes only the
configured five-to-eight data bits, but previously calculated odd/even parity
from all eight bits of the supplied byte.  A high bit outside the configured
character width could therefore change the transmitted parity bit even though
that high bit was not present in the frame.

The VT340 exposes the defect with an SCN2681 configured for seven data bits
and odd parity.  It writes `a6`; the serialized data is `26`.  The old code
counted four one bits in `a6` and emitted parity one, while the seven-bit value
`26` has three one bits and requires parity zero.  Both local-loopback
channels consequently reported a parity error.

### Current correction

Mask the supplied value to `m_df_word_length` and use that framed value for
odd/even parity calculation.  Mark, space, and no-parity modes are unchanged.

This correction was accepted upstream as MAME pull request
[#16726](https://github.com/mamedev/mame/pull/16726), merge commit
`034db06a61debb37cddbadeea8e937818627b422`.  The VT340-only transmit-register
masking used during review has been removed; the driver now relies on the
shared serial implementation.

### Minimal focused regression

Add a direct `device_serial_interface` framing test covering at least:

- seven-bit odd parity with `a6`, proving that the unused high bit cannot
  affect parity;
- seven-bit even parity with the same value;
- an eight-bit case proving no behavior change at full width; and
- preferably a five- or six-bit boundary case.

The test should inspect the generated frame bits rather than depend on a
particular machine driver.  Then run the VT340 SCN2681 integration regression:

```text
vt340-research/tests/phase4-scn2681-loopback.sh
```

Expected VT340 integration result: both channels complete all 21 transfers,
status is `0d` before each receive read, and no `70` error bits occur.

### Evidence

- `vt340-research/traces/phase4-scn2681-loopback-report.md`
- upstream implementation: `src/emu/diserial.cpp`
- Philips SCN2681 product specification: character length and parity fields

## 2. MCS-51 SBUF receive/transmit latch separation

### Problem

The MCS-51 architecture uses the SBUF address for two physically distinct
registers selected by access direction.  A write loads the transmit register;
a read returns the receive latch.  The earlier MAME implementation assigned a
transmitted byte to `m_sbuf`, so an immediate SBUF read incorrectly echoed the
new transmit byte even if no character had been received.

The VT340 native negative-loopback diagnostic makes this visible: it writes
`55` to SBUF and expects the receive latch to remain `00`.  The old behavior
reported a false received byte and caused the firmware error path.

### Current correction

`sbuf_w` passes the written value to the transmit state machine without
changing `m_sbuf`.  The receive-completion paths remain the writers of
`m_sbuf`, and `sbuf_r` continues to return it.

### Minimal focused regression

Create a core-level UART/SFR test that:

1. establishes a known receive-latch value;
2. writes a different value to SBUF;
3. reads SBUF before reception completes and observes the old receive value;
4. verifies that the newly written value is still transmitted; and
5. completes a receive operation and observes the new received value.

Also exercise save/restore while transmit and receive state differ.  The
VT340 Phase 3 checkpoint is useful integration coverage after the direct test.

### Evidence

- provenance commit `beb58c4b`
- `vt340-research/firmware/wait-to-ok.md`
- current implementation: `src/devices/cpu/mcs51/i8051.cpp`
- Intel MCS-51 documentation describing separate receive and transmit buffers

## 3. SCN PCI/ACI reset-error command must not remain latched

### Problem

`scn_pci_device::write_command` stored the new command using
`std::exchange(m_command, data)`, then attempted to clear the instantaneous
reset-error bit by modifying the now-old local `data` value.  The stored
`m_command` therefore retained bit 4 even though reset-error is a command, not
a persistent operating-mode bit.

This is an implementation error independent of the VT340 and independent of
the SCN2641 mode-register issue.

### Current correction

Clear bit 4 in `m_command` after performing the error reset.  Do not alter any
other persistent command bits.

### Minimal focused regression

For each applicable PCI/ACI variant, write a command containing reset-error
and persistent enable/mode bits, then verify:

- the error state is cleared;
- a command-register read omits the reset-error bit; and
- all persistent bits retain their written values.

This should be a separate patch even if the same test fixture later hosts the
SCN2641 cases.

### Evidence

- `vt340-research/traces/phase4-scn2641-printer-report.md`
- current implementation: `src/devices/machine/scn_pci.cpp`
- Signetics SCN2641 command-register description

## 4. Independent SCN2641 mode registers

### Problem

The shared PCI/EPCI/ACI implementation contains an undocumented SCN2651-family
behavior, verified on that hardware, in which writing MR1 transfers the old
MR1 value to MR2.  It previously applied the same behavior to the
asynchronous-only SCN2641.

The SCN2641 documentation describes independent MR1/MR2 accesses.  The VT340
firmware relies on that contract: it writes MR2, resets the mode pointer, and
then writes MR1.  Copying the former MR1 reset value into MR2 erases the baud
configuration and prevents serialization.

### Current correction

For the ACI/SCN2641 path, an MR1 write updates MR1 and advances the mode
pointer without changing MR2.  The verified PCI/EPCI transfer behavior is
left intact.

### Minimal focused regression

Instantiate an SCN2641, write distinct MR2 and MR1 values using the documented
pointer sequence, and prove both values are retained and used.  Include a
short asynchronous transfer using the selected MR2 baud source.  Add a
PCI/EPCI case confirming that their existing verified transfer behavior is
unchanged.

Audit and smoke-test known SCN2641 consumers, including:

- `src/mame/acorn/accomm.cpp`
- `src/mame/microterm/mt420.cpp`

Then run the VT340 printer regression.

### Evidence

- `vt340-research/traces/phase4-scn2641-printer-report.md`
- `vt340-research/tests/phase4-scn2641-printer.sh`
- current implementation: `src/devices/machine/scn_pci.cpp`
- Signetics SCN2641 mode-register sequencing

## 5. SCN2641 invalid reset mode must remain idle

### Problem

The shared implementation interpreted cleared MR1 bits `00` as the
PCI/EPCI synchronous mode.  On an SCN2641 those bits describe an invalid mode:
the device is asynchronous-only.  Immediately after reset, the old behavior
therefore emitted synchronous zero/SYN traffic before software had configured
a valid asynchronous format.  The serializer could still be mid-character
when the first legitimate transfer began, producing bad data and a framing
error.

### Current correction

The SCN2641 transmitter and receiver update paths remain idle while the mode
field is `00`.  PCI/EPCI synchronous behavior is unchanged.

### Work needed before submission

This item is well supported by the VT340 trace and the SCN2641 mode table, but
it deserves a focused reset-state test and a careful check of enable/disable
transitions before it is treated as upstream-ready.  Verify:

- reset produces no TxD character activity before valid mode programming;
- enabling the transmitter in invalid mode does not start a frame;
- programming a valid asynchronous mode starts from a clean serializer state;
- disabling and re-enabling a valid configuration preserves documented
  behavior; and
- PCI/EPCI synchronous startup is unaffected.

### Evidence

- `vt340-research/traces/phase4-scn2641-printer-report.md`
- `vt340-research/tests/phase4-scn2641-printer.sh`
- current implementation: `src/devices/machine/scn_pci.cpp`
- Signetics SCN2641 reset state and asynchronous mode table

## 6. Proposed MCS-51 external MOVX bus-cycle interface

### Why an interface is needed

The VT340 schematic connects CPU1 T0 to the active-low external-memory board
read strobe (`P1 BRD`).  Firmware routine `3939-3947` observes that signal
around two MOVX probes.  The present MCS-51 interface invokes the external
address-space access atomically; the machine driver cannot observe the
internal read-strobe phase.

The VT340 driver consequently retains one explicitly documented compatibility
accommodation: the read at PC `3941` records the board-read event, and the P3
sample at PC `3940` consumes it as a low T0 observation.  Several
PC-independent driver-only substitutes were tested and rejected because they
were consumed at the wrong internal callback, created an extra timer edge, or
depended on unstable callback timing.

### Proposed scope

Investigate a small, optional MCS-51 core interface that exposes the physical
external data-memory cycle sufficiently for board wiring to observe read and
write strobes.  Candidate forms include:

- separate optional active-level read- and write-strobe callbacks; or
- one callback carrying address, direction, and a documented bus-cycle phase.

Do not choose the API solely around the VT340.  Before implementation, inspect
MAME conventions for CPU bus/status callbacks and identify whether consumers
need assertion and release edges, an address-valid phase, or only a cycle
notification.  The result must define ordering relative to the external
address-space handler and port/timer sampling.

### Core cases to audit

- `MOVX A,@DPTR` and `MOVX @DPTR,A`
- `MOVX A,@R0/@R1` and `MOVX @R0/@R1,A`
- read versus write assertion and release ordering
- address formation involving P0/P2 and any existing port callbacks
- debugger/disassembly reads and side-effect suppression
- timer/counter sampling when a strobe is physically wired to T0/T1
- save states during or adjacent to an external cycle
- cycle accounting and interrupt boundaries
- zero-overhead or near-zero-overhead behavior when no callback is bound

### Acceptance test

Wire the VT340's board-read signal through the generic interface, remove both
the `3940` and `3941` PC checks, and demonstrate:

- the native Phase 2 and Phase 3 cold-boot checkpoints still pass;
- no artificial pulse width or instruction-address dependency remains;
- T0 observes the physical strobe without introducing an extra counter edge;
  and
- other MCS-51 systems retain their prior behavior when callbacks are unused.

This is a design task, not yet a ready patch.  It should follow the smaller
proven fixes above so review of those changes is not coupled to a new CPU bus
API.

### Evidence

- `vt340-research/hardware/cpu-communication.md`, section "CPU1 board-read
  strobe cleanup experiment"
- `vt340-research/SPRINT_STATUS.md`, remaining compatibility accommodations
- current VT340 hook: `src/mame/dec/vt340.cpp`

## Changes that should remain VT340-specific

The following work is not currently a candidate for a shared-device patch:

- SCN2641 and SCN2681 address decoding, modem pin levels, clocks, and
  interrupts defined by the VT340 schematic;
- resolved DAT9 ownership and the CPU1/CPU2/board wiring around that net;
- DC323 POST/test modes and raster behavior, for which no generic MAME device
  currently exists;
- LK201 attachment and terminal-port wiring;
- E80 EEPROM/NVRAM mapping;
- VT340 shared-memory arbitration approximations; and
- pulse retention used to preserve short board events across scheduler
  timeslices.

The reserved MCS-51 SFR `c2` returning `ff` is also not ready for upstream
core treatment.  It is presently a local VT340 open-bus observation and lacks
sufficient silicon-wide evidence to define generic MCS-51 behavior.

The switch from an 8032 declaration to the schematic-correct 8031 is a machine
configuration correction, not a CPU-core change.

## Suggested upstream sequence

Prepare and validate these as separate branches or commits in this order:

1. configured-width parity in `device_serial_interface`;
2. MCS-51 SBUF receive/transmit separation;
3. SCN PCI/ACI reset-error command latching;
4. SCN2641 independent mode-register behavior;
5. SCN2641 invalid-mode reset idling; and
6. MCS-51 MOVX strobe design proposal, followed by implementation only after
   the callback contract is clear.

For every item, record:

- the exact pre-fix failing state;
- the specification rule being modeled;
- why the patch is the smallest correction;
- direct test results;
- affected-device build/smoke results; and
- the VT340 integration result where relevant.

An item is ready for submission only when it stands on its shared-device
behavior without requiring reviewers to understand the full VT340 startup
sequence.
