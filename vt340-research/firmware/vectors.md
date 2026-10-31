# Vector notes

The candidate vector bytes are generated with:

```sh
python3 vt340-research/tools/analyze_vectors.py roms/vt340/e1.bin roms/vt340/e3.bin
```

Only the reset long jumps are currently proven instruction boundaries:

- E57 / CPU1: `0000: LJMP 0238`
- E24 / CPU2: `0000: LJMP 0212`

Do not infer interrupt-handler entry points from isolated bytes until a full
8051 disassembly confirms control flow around the vector slots.
