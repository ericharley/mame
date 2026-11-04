# VT340 ROM catalog

This directory tracks ROM **metadata**, not copyrighted binary images. Local
images live under the repository's ignored `roms/` directory.

The layout separates three concepts:

```text
vt340-research/roms/                 tracked metadata
  catalog.json                       sets and working profiles
  sets/*.json                        release/component manifests

roms/library/                        ignored versioned binary library
  vt340/v1.1-research/*
  lk201/mame-reference/*

roms/vt340/ and roms/lk201.zip       ignored active MAME layout
```

A **set** describes one independently identifiable firmware or peripheral
collection. A **profile** selects compatible sets for one emulator run. This
matters because the current working baseline is composite: the cartridge ROMs,
character generator, EEPROM, and keyboard images are compatible, but are not
proven to have come from one physical terminal.

Use the catalog tool from the MAME checkout root:

```sh
# Show known sets and profiles.
vt340-research/tools/rom_catalog.py list

# Import the currently active MAME ROMs into versioned local storage.
vt340-research/tools/rom_catalog.py import-current

# Verify the versioned library or active MAME layout.
vt340-research/tools/rom_catalog.py verify
vt340-research/tools/rom_catalog.py verify --location active
vt340-research/tools/rom_catalog.py verify --profile vt340-v1.1-working --location active

# Materialize a named profile into roms/vt340 and roms/lk201.zip.
vt340-research/tools/rom_catalog.py activate vt340-v1.1-working
```

Import never replaces a different existing library image. Activation verifies
every source image, stages the complete result, and then replaces only the
catalogued active files. Other ROM sets under `roms/` are untouched.
`--binary-root PATH` may be placed before a command to exercise activation in
an isolated directory.

To add a future version:

1. Create a set manifest under `sets/` with the source filename, board
   component, size, CRC-32, SHA-1, SHA-256, provenance, and dump condition.
2. Add the set to `catalog.json` with a unique `library_path`.
3. Add a profile only after compatibility is established.
4. Place the binaries in the corresponding ignored `roms/library/` directory,
   or extend the importer for its source format.
5. Run `rom_catalog.py verify` before using or comparing the set.

Never infer that identically named sockets imply identical firmware. Preserve
original dump bytes and source names, record any normalization separately, and
represent reconstructed images as derived artifacts rather than overwriting the
source dump.
