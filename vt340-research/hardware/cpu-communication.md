# Interprocessor communication

The two CPU buses reach a confirmed shared 64 KiB RAM made from E93/E94 (two
64K x 4 devices).  Schematic page 21 multiplexes AA and BA address inputs and
uses separate latches/transceivers for the two data paths.  The first driver
models the common storage but not contention or arbitration timing.  Firmware
traces and the remaining control sheets are still needed before assigning
mailbox semantics.

CPU2 P1 is the high byte/status latch for 16-bit video accesses.  Schematic
reinspection corrected the direct CPU connection: P1.1 carries
`P2 DAT9/STATUS H` to CPU1's external T1 input.  CPU1 INT0 and INT1 instead
come from the 2681 and 2641 serial devices.  The driver latches CPU2 P1 for
firmware readback and drives CPU1 T1 from P1.1.  The POST protocol is
bidirectional: CPU2 pulses P1.1 in routine `1701`, while CPU1 acknowledges by
pulling P3.5/T1 low in routines `3919` and `3b8e`.  Pulse latches preserve
these sub-millisecond events across MAME timeslice boundaries.

DAT9 startup ownership is now explicit and independent of firmware addresses.
The resolved level is low if CPU1 P3.5, CPU2 P1.1, or the selected board/DC323
phase drives low; otherwise it is high.  CPU2's first external read retains
the `P2 BRD L` low phase until the following port sample.  CPU2's startup
pulse then receives the board-turnaround low phase.  After `F072=ff` releases
DC323 reset, the second `F060=00` board-control initialization produces the
high/low completion pair and leaves the net to the two processor ports.  The
same resolved value feeds CPU2 P1.1 reads, CPU1 P3.5 reads, and CPU1's external
T1 input.  This replaces the former PC-qualified values at `126f`, `1297`,
`129a`, and `1700`.

CPU1 P1.6 is the schematic `P1 CPMRESET H` output, not a configuration input.
The CPU1 firmware drives it and later snapshots its state into shared `e795`;
the driver correctly returns the live 8031 port latch for that read.

The first confirmed software mailbox is shared RAM `7ff1`.  CPU1 writes `ff`
and polls for completion; CPU2 ROM clears it in its initialization/service
path.  The DC323 E70 also drives CPU2's active-low INT0 input as
`P10 INTRREQ L`.  The ROM now clears its ROM, bitmap, DC7051-register, and
vertical-period POST checks and completes the final DAT9 status/report phase.
DC323 register 3 is a read-status/write-zero-to-clear register during normal
operation. Pause Complete in bit 0 selects firmware acknowledgement `fe`;
Scroll Service in bit 1 selects `fd`. If both are pending at a frame boundary,
the level-triggered handler runs once for each condition and then releases
INT0. An older PC-qualified bit-0 inversion incorrectly forced both entries
down the `fd` path, left bit 0 pending indefinitely, and starved CPU2's packet
dispatcher. Removing it lets CPU2 drain all startup ring packets natively.
