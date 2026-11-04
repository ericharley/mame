# Optional fast-start ROM patch

## Purpose

The normal driver preserves the reconstructed VT330/VT340 V1.1 firmware and
its missed `7ff2` checkpoint. That path eventually succeeds, but only after
CPU1 exhausts its approximately 120-second fallback.

For interactive use, the driver offers an explicit optional ROM compatibility
patch under **Machine Configuration → Startup Checkpoint Workaround**. Select
**Skip Missed Checkpoint**, then reset the terminal. The original ROM behavior
remains the default.

## Patch

CPU1 normally executes:

```text
3A08  MOV  DPTR,#7FF2
3A0B  MOV  A,#10
3A0D  MOVX @DPTR,A
3A0E  LCALL 3AC9
3A11  LCALL 3B8E
3A18  MOVX A,@DPTR       ; wait for checkpoint zero
...
3A31  MOVX A,@DPTR       ; wait for final nonzero result
3A3A  CJNE A,#80,3A4A   ; classify success/error
```

The patch changes only the immediate operand at logical E1 address `3a0c`:

```text
10 -> 00
```

CPU1 therefore places the already-issued checkpoint value at the firmware's
decision point. It leaves both polling stages, CPU2's final result writer, and
CPU1's `80` success comparison intact. The driver recomputes E1's native
rotate/XOR checksum after applying or removing the patch on reset.

This is deliberately not presented as recovered hardware behavior. It is a
user-selectable ROM workaround for the unresolved V1.1 startup ordering.

## Verification

`tests/fast-start.sh` uses a clean configuration and NVRAM directory. The
verified path is:

| Emulated time | Event |
|---:|---|
| 8.295768 s | patched CPU1 write stores `7ff2=00` |
| 8.309672 s | CPU1 leaves the checkpoint wait |
| 13.194729 s | native CPU2 code writes final result `80` |
| 13.194736 s | CPU1 classifies authentic `80` |
| 13.194742 s | CPU1 enters native success routine `4551` |
| 17.177906 s | CPU1 submits command 32 |
| 17.198947 s | native PBT transfer completes |

The focused fast-start regression and the existing PBT provenance trace both
pass. Selecting **Original ROM Wait (~120 Seconds)** restores byte `10`,
recomputes the checksum, and retains the research baseline.
