# Initial firmware analysis

> Historical checkpoint: this records the first executable model and is
> intentionally not the current hardware map.  Later work identified the
> mirrored block as the DC323, corrected the P3.3 bank signal, completed POST,
> and reached visible E49 text.  See `../hardware/video-hardware.md` and
> `../milestones.md` for current results.

## Inventory

At this historical checkpoint, all six available images were exactly 32 KiB
and E80 had not yet been acquired. The later recovered E80 image and canonical
hashes/provenance for every current set are recorded in `../roms/catalog.json`
and `../roms/sets/`. Recompute raw-image hashes with `tools/inspect_roms.py`.

## CPU assignment and program map

| Image | Assignment | Address | Confidence | Evidence |
|---|---|---:|---|---|
| E1 | E57 / processor 1 | `0000-7fff` | Confirmed | J5 pins use AA/AAD bus; `/CE` is AA15 H |
| E2 | E57 / processor 1 | `8000-ffff` | Confirmed | J5 pins use AA/AAD bus; `/CE` is AA15 L |
| E3 | E24 / processor 2 | `0000-7fff` | Confirmed | J5 pins use BA/BAD bus; `/CE` is BA15 H |
| E4 | E24 / processor 2 | `8000-ffff`, bank 0 | High | `/CE` is B0SEL L; B0SEL equation is on schematic page 20 |
| E5 | E24 / processor 2 | `8000-ffff`, bank 1 | High | `/CE` is B1SEL L; B1SEL equation is on schematic page 20 |
| E49 | video/character path | not CPU program space | Confirmed | Dedicated 27256 on video schematic page 28 |

The bank-select equations are `B0SEL_L = BA15_L OR ROMBANK0_L` and
`B1SEL_L = BA15_L OR ROMBANK1_L`.  With the five-27256 cartridge strap,
ROMBANK0 is the complement of processor-2 T0/P3.4 (ROMBANK1).  A controlled
boot comparison resolves the signal-name ambiguity: P3.4 high selects E5 and
P3.4 low selects E4.  E5 produces the coherent reset path and reaches the
DC7051 status poll at `c048`; E4 immediately enters an overlapping instruction
stream and corrupts control flow.  See `bank-polarity-investigation.md`.

## Reset and vectors

8051 reset is program address zero.  E1 begins `02 02 38`, an `LJMP 0238`.
E3 begins `02 02 12`, an `LJMP 0212`.  Both have plausible 8051 interrupt
vector regions, unlike E2/E4/E5 at offset zero.  This independently supports
the schematic-derived lower-ROM assignment.

Observed vector candidates:

- CPU 1 / E1: reset `LJMP 0238`; vector 0003 starts `DA D2 58...`; 000b
  begins `20 C0 E0...`; 0013 begins `FF D2 58...`; 001b begins `FF 32`;
  0023 is `FF 32`.  Several entries appear to depend on bytes immediately
  before the architectural vector, so full disassembly is required before
  assigning interrupt names.
- CPU 2 / E3: reset `LJMP 0212`; 0003 begins `5F 12 00 91...`; 000b begins
  `00 02 03 DE...`; 0013 is zero-filled; 001b is zero-filled; 0023 begins
  `00 02 05 82...`.  As above, these are candidates, not labeled routines.

## Known early dependencies

The first trace proved that both reset paths immediately require external RAM.
The first-stage driver therefore models the confirmed E93/E94 shared 64 KiB
RAM and logs a bounded sample of accesses when diagnostic logging is enabled.
The first register overlay is now modeled as a 64-word DC7051 register file.
CPU2 P1 supplies each register's high byte and MOVX supplies its low byte;
register 3 returns the status bit (`10`) expected by reset firmware.  CPU2
P1.1 `P2 DAT9/STATUS H` also drives CPU1's external T1 input.  EEPROM,
serial hardware, DC7051 timing semantics, bus contention, and most board-
control latches remain unmodeled.

## First executable checkpoint

A one-second headless run reaches both firmware streams with authentic ROM
bytes and the shared RAM enabled.  CPU1 begins by writing `90` to XDATA `0000`
from PC `0201`, then touches `ecc8` and a working area at `4c00-4cff`.  CPU2
executes the E5 upper bank, polls DC7051 register 3 at `ff03`, and writes
16-bit values to registers 2a, 2b, 20, and 21.  With the CPU1 reserved-SFR
response corrected, the timed stop advances to CPU1 `9079`; CPU2 remains near
`e6e0`, with interrupts disabled, and CPU2 bank 1 (E5) is still selected.
CPU1 is polling shared mailbox byte `7ff1` after posting `ff`; CPU2 has not yet
reached either ROM path that clears it.  See
`traces/boot-summary.md` for the command and caveats.

The run is deterministic as a smoke checkpoint, not a claim that POST has
passed.  The earlier flood of CPU2 indirect writes to internal addresses
`80-ff` was caused by selecting E4 at reset, not by authentic initialization.
Correcting the bank polarity eliminates those CPU2 diagnostics.  The driver
remains an 8031 because the schematic, parts list, and Intel device definitions
agree.  `internal-ram-investigation.md` records how the misleading CPU2
symptom was resolved.  CPU1's later stack growth was localized to an
overlapping formatter path at `09e4` and resolved by the target's all-ones
reserved-SFR `c2` behavior; `cpu1-stack-investigation.md` records the trace,
controlled 8052 comparison, and new mailbox checkpoint.

## Unresolved questions

- Exact external data-memory decoding beyond the DC7051 register window.
- Whether the cartridge-size strap has any alternate production configuration.
- Reset contents and firmware initialization path for E80.
- Semantics of CPU1 and CPU2 port pins beyond the bank and P1 status path.
- DC323 register/status behavior and the condition that completes CPU2
  graphics initialization before mailbox service.
