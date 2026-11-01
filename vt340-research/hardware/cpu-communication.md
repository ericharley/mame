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

CPU1 P1.6 is the schematic `P1 CPMRESET H` output, not a configuration input.
The CPU1 firmware drives it and later snapshots its state into shared `e795`;
the driver correctly returns the live 8031 port latch for that read.

The first confirmed software mailbox is shared RAM `7ff1`.  CPU1 writes `ff`
and polls for completion; CPU2 ROM clears it in its initialization/service
path.  The DC323 E70 also drives CPU2's active-low INT0 input as
`P10 INTRREQ L`.  The ROM now clears its ROM, bitmap, DC7051-register, and
vertical-period POST checks and completes the final DAT9 status/report phase.
DC323 register 3 has distinct write-control and read-status semantics: during
a frame request its status bit 0 reads low even though the preceding `fffd`
acknowledge left bit 0 high in the write latch.  Returning the latch verbatim
caused two level-triggered interrupt entries per frame and eventual stack
overflow.  With status readback separated, every request receives one
acknowledge and CPU2 remains in its interrupt-enabled E4 operational loop.
