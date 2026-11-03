# Native Set-Up screen completion

## Result

The LK201 Set-Up key and original VT340 firmware now display the complete
`SET-UP DIRECTORY`.  No Set-Up text, key-specific display trigger, timing
delay, or PC-qualified status value is injected.

The failure was a stopped foreground-firmware handshake, not a missing key
mapping or scanout-page feature.  F3 already reached CPU1 as the correct LK201
code `58`, but CPU1 and CPU2 were blocked behind two unimplemented DC323
completion conditions.

## Firmware path

CPU1 dispatches LK201 code `58` through:

```text
61b7  compare A with 58
61ba  jump 654b
6557  set internal bit 29.2 (Set-Up request)
4973  foreground loop observes bit 29.2
4a1b  enter Set-Up transition
c1bc  construct the native Set-Up state
```

Before the correction, the request bit was set by the interrupt-driven
keyboard path, but the foreground loop could not observe it:

```text
CPU1 EC30/EC31: wait for shared 4be5 to change from 01 to 02
CPU2 EF11/EF12: wait for DC323 status bit 2
```

The Dragon specification identifies status bit 2 as **Rasterop Initialization
Complete**.  Loading a rasterop clears it; completing initialization sets it.
The emulator executes rasterops synchronously, so it now clears completion at
command load and asserts initialization, rasterop, and address completion when
the operation has finished.

That exposed the next native operation rather than bypassing it.  CPU2 issued
command `0bc4`, a bitmap-to-processor transfer from off-screen bitmap origin
`(800,1506)`, extent `8x25`, and waited at `2b2f/2b30` for status bit 5.  Bit 5
is **I/D Data Receive Ready** and must track data in the six-word I/D FIFO.

Register 7 now streams eight-pixel bytes from either E49 or ordinary bitmap
memory.  A bitmap-to-processor command clears FIFO-ready, then asserts it while
data is available.  Reading the final byte clears FIFO-ready and asserts
Address Output Complete.  The existing E49 startup-string transfer uses the
same path.

## Visible result

The deterministic run posts Tab at 130 seconds and F3 at 140 seconds.  At
142.010332 seconds it records:

```text
LK201 Set-Up code:                 58
Rasterop Initialization Complete: observed
I/D Data Receive Ready:           observed
shared barrier 4be5:               00 (released)
visible framebuffer hash:         514C8F54
lit visible pixels:                43231
```

The firmware-rendered screen contains `SET-UP DIRECTORY`, `VT330 Version
V1.1`, all native Set-Up categories and actions, the instructions, copyright,
and the status row.

## Regression

Run from the MAME root:

```sh
vt340-research/tests/setup-screen.sh ./vt340
```

The test uses `traces/setup-screen-trace.lua` and checks key delivery, both
documented completion conditions, released synchronization state, and the
complete visible framebuffer signature.
