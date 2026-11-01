# VT340 EPROM dump reconstruction

## Dump mechanism

The published E1-E5 files are not ordinary linear EPROM images. The Arduino
reader changes the high address port before the low address port and samples
immediately. Except for the first byte, ordinary reads therefore appear one
byte late. The old driver compensated with a one-byte rotation.

That rotation is insufficient at a 256-byte page transition. While the high
port already contains `xx`, the low port still contains `ff`, so raw offset
`xx00` samples authentic logical `xxff`. A blanket one-byte rotation instead
uses raw `(xx+1)00`, substituting the following page's final byte.

The reconstruction now retains each raw dump in its own ROM region and builds
the executable regions in `init_vt340`:

1. Shift raw bytes 1 through 7fff down by one address.
2. For pages 01 through 7e, replace logical `xxff` with raw `xx00`.
3. Apply the independently established E4 descriptor repair at `622d=02`.
4. Reconstruct the uncaptured final byte using the ROM's rotate/XOR POST.

The original dump files remain unmodified.

## Audit result

Each ROM has 126 mechanically recoverable page-final positions, from `01ff`
through `7eff`. Some replacements have the same byte value; the table counts
the positions whose value actually changes.

| ROM | Recoverable positions | Values changed | Logical `00ff` retained | Rebuilt `7fff` |
|---|---:|---:|---:|---:|
| E1 | 126 | 124 | `ec` | `8e` |
| E2 | 126 | 121 | `43` | `77` |
| E3 | 126 | 125 | `ff` | `62` |
| E4 | 126 | 125 | `6c` | `eb` |
| E5 | 126 | 118 | `e4` | `6e` |

This changes 613 page-final bytes across the five ROMs. The five logical
`00ff` bytes do not have an earlier page-transition sample and cannot be
recovered by this mechanism. Their retained values decode coherently in
context: E1 and E2 complete immediate/call operands, E3 is in an `ff` fill
area, and E4/E5 continue valid instruction streams. They remain explicitly
classified as structurally supported rather than independently recovered.

The final `7fff` byte of each ROM was never sampled. Firmware seeds are E1=7,
E2=8, E3=7, E4=8, and E5=9. The table's tail values make the complete
rotate/XOR result zero after all boundary restoration and the E4 descriptor
repair.

## Independently observed anchors

The generalized transform reproduces every boundary repair previously proven
from native control flow:

| ROM byte | Reconstructed | Firmware effect |
|---|---:|---|
| E1 `38ff` | `78` | Restores `MOV R0,#55`; CPU1 reaches `CLR P1.0` and releases CPU2 reset |
| E2 `3bff` | `1f` | Restores the `be1f` table helper target |
| E3 `14ff` | `e5` | Continues `MOV A,DPL` instead of returning through an empty frame |
| E3 `15ff` | `22` | Restores the timeout routine's `RET` |
| E3 `28ff` | `e0` | Restores `MOVX A,@DPTR` in the poll routine |
| E3 `30ff` | `80` | Restores `SJMP 3119` |
| E3 `48ff` | `75` | Restores `MOV P1,#00` |
| E4 `12ff` | `f0` | Restores the dispatcher packet-length store |
| E5 `72ff` | `09` | Restores the eight-entry mask-loop terminator |

It also repairs CPU1 `3aff`, which had made the successful initial UART/POST
path fall into the error reporter. With the full reconstruction, CPU1 releases
CPU2 at 0.558338 s and the native DAT9 rendezvous reaches its success path at
0.573882 s.

Run `vt340-research/tests/rom-boundary-audit.sh` to reproduce the counts,
anchors, checksum tails, and zero final checksums from the unmodified dumps.
