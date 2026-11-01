# VT340 terminal-control PAL analysis

## Recovered sources

Three VT340 JEDEC dumps are archived by 9track.net:

| DEC part | SHA-256 | Local research source |
|---|---|---|
| `23-168K5` | `852dc05b39dc6b877d68574b3adc39eb46434ee7f8751ddde022fa540d6362be` | `../sources/pal/23-168K5.jed` |
| `23-335J5` | `634a4b9d8ec32058014823cac0c14ee02e67983bf11835c94e892e65d1e3c61f` | `../sources/pal/23-335J5.jed` |
| `23-336J5` | `499c9f725513f11d509e4b40c223a752932ecb9eb809e4e76a7bc80e4d9e0e0e` | `../sources/pal/23-336J5.jed` |

The files came from `https://www.9track.net/roms/files/dec/vt340/` and are
kept outside the MAME Git repository with the other source material. MAME's
`jedutil` decodes all three 2048-fuse images.

The DEC ROM catalog identifies `23-168K5` as schematic location E58. Its
PAL16R8 equations and pin use match E58's registered memory-controller state
machine exactly. `23-335J5`, decoded as PAL16L8, matches every E78 schematic
input and output including the CPU1/CPU2 read, write, and I/O decode terms.
`23-336J5` has not yet been assigned to a schematic location.

## E58 memory-cycle inputs

The schematic maps the important E58 pins as follows:

| PAL input | Signal |
|---|---|
| `i2` | delayed `P1 ARD L` from E59 |
| `i3` | `P2 BRD L` |
| `i4` | `P2 BALE H` |
| `i5` | `P1 MDA H` |
| `i6` | `P2 DAT10/MDB H` |
| `i7` | `P2 PBIOSEL L` |
| `i8` | `P2 LASTBANKEN L` |
| `i9` | `P2 BA11 H` |

E58 pin 12 is the active-low `P3 WDS L` output. `jedutil` recovers its
registered equation as:

```text
/WDS := delayed_P1_ARD & P1_MDA
      + /P1_MDA & state_R2
```

For a CPU1 external write, `P1 ARD L` is deasserted high and the observed
CPU1 P1 latch is `dc`, so `P1 MDA` (P1.2) is high. E58 therefore asserts WDS.

## E78 shared-RAM write enable

The schematic maps E78 inputs used by the write equation as:

| PAL input | Signal |
|---|---|
| `i1` | `P1 AIOSEL L` |
| `i3` | `P1 AWR L` |
| `i4` | `P3 BIOSEL L` |
| `i6` | `P3 WDS L` |
| `i7` | `P2 BWR L` |

E78 pin 13 drives active-low DRAM write enable `P3 MWR L` to both E93 and
E94. The recovered `23-335J5` equation is:

```text
/MWR = P1_AIOSEL & /P1_AWR & /WDS
     + P3_BIOSEL & /WDS & /P2_BWR
```

Signal names ending in `L` are already active-low physical pins. For CPU1's
external-memory write to `7ff2`, `AIOSEL L` is deasserted high, `AWR L` is
asserted low, and E58 asserts `WDS L` low. The first product term therefore
asserts `MWR L` and writes E93/E94.

## Phase 4 consequence

The controlled request-visibility experiment proves that retaining zero
across CPU1's `7ff2=10` write is sufficient for firmware to continue, but the
recovered PAL equations reject that behavior as a physical explanation. The
real controller generates a DRAM write cycle for this CPU1 MOVX operation.
The driver must not suppress, redirect, or discard the request write.

The remaining plausible timing branch is earlier: real execution must allow
CPU1 pulse 6 and a following DAT9 response before CPU2's `136d` clear. Since
the CPU and PAL clocks are both derived from the documented 12 MHz oscillator,
the next audit should concentrate on CPU2's DC323 table-transfer duration and
external DAT9 ownership, not on shared-RAM write loss.
