# Processor 1 memory map (E57)

## Program space

| Range | Device | Status |
|---:|---|---|
| `0000-7fff` | cartridge E1 | Confirmed |
| `8000-ffff` | cartridge E2 | Confirmed |

J5 routes AA0-AA14, AAD0-AAD7, and APSEN L to E1/E2.  E1 `/CE` is AA15 H
(active when address bit 15 is low); E2 `/CE` is AA15 L.

## External data space

| Range | Device | Status |
|---:|---|---|
| `0000-ffff` | shared E93/E94 RAM | Confirmed physical RAM; register overlays unresolved |

E93 and E94 are 64K x 4 RAMs.  Page 21 multiplexes their address inputs
between processor 1's AA bus and processor 2's BA bus and connects both data
paths through latches/transceivers.  The first implementation treats the full
64 KiB as shared RAM.  Peripheral/register overlays remain to be decoded.
