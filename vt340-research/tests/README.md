# VT340 test and evidence system

All runnable VT340 tests are catalogued in `manifest.json` and executed through
`run.py`. Existing shell scripts remain valid standalone entry points, but the
common runner is preferred because it records reproducible run metadata and
preserves evidence.

Run commands from the MAME checkout root:

```sh
# Inventory tests, categories, durations, and suites.
vt340-research/tests/run.py list

# Run the short default suite.
vt340-research/tests/run.py run

# Run named suites or tests.
vt340-research/tests/run.py run core
vt340-research/tests/run.py run graphics serial
vt340-research/tests/run.py run conformance
vt340-research/tests/run.py run dc323-device graphics-raster-commands

# Run an individual external-corpus Tektronix case.
VT340_CORPUS_CASE=tek-basic-vectors vt340-research/tests/vt340test-corpus.sh ./vt340
VT340_CORPUS_CASE=tek-usa-map vt340-research/tests/vt340test-corpus.sh ./vt340

# Explain and reproduce VT340 Pan Down/Up behavior versus VTTEST 11.2.2.
# See vttest-pan.md before treating its diagonal-star result as a failure.
sh vt340-research/fixtures/vttest-pan.sh pan-down

# Isolate VTTEST 11.2.3's unsupported DECALN prefill from page formatting.
# See vttest-page-format.md for the valid VT340 page sizes and expected result.
sh vt340-research/fixtures/vttest-page-format.sh lines-36-message

# Verify native normal/bold/underline/reverse/blink rendering and palette routing.
vt340-research/tests/run.py run text-attributes
vt340-research/tests/run.py run color-map-redraw
vt340-research/tests/run.py run dc323-command-coverage
vt340-research/tests/run.py run dc7051-timing

# Use another targeted executable or result location.
vt340-research/tests/run.py run core --binary ./vt340 \
  --results /tmp/vt340-results
```

Suite selectors may optionally use an `@` prefix, such as `@quick`. Selecting
`all` runs every atomic test once. Compatibility aliases and legacy aggregate
wrappers are omitted from suite expansion to avoid duplicate multi-minute
runs; name one explicitly when it is needed.

## Result layout

The default output is ignored by Git and grouped by UTC timestamp and source
revision:

```text
vt340-research/test-results/
  20261104T180000Z-1a2b3c4d/
    run.json
    summary.json
    report.md
    dc323-device/
      metadata.json
      stdout.log
      stderr.log
      artifacts/
    graphics-raster-commands/
      metadata.json
      stdout.log
      stderr.log
      artifacts/
        mame.log
        events.jsonl
        graphics-115.png
        graphics-124.png
        graphics-130.png
```

`run.json` identifies the host, platform, Git revision, dirty-worktree state,
selection, and manifest. `summary.json` records the complete result set.
`report.md` provides a compact result table and an inline gallery of every PNG
produced by the selected tests.
Every test's `metadata.json` records its exact command, start/end timestamps,
duration, exit status, manifest entry, and SHA-256, size, and media type for
each captured file.

The runner supplies `VT340_TEST_ARTIFACT_DIR` to each script. Tests with
internal MAME logs, structured JSON events, EEPROM images, or screenshots copy
them there before removing temporary state. A successful test is changed to a
failure if an output declared by the manifest was not produced. This prevents
a visual regression from passing merely because its screenshot silently went
missing.

Raw run artifacts are not checked into Git. Stable input fixtures and source
images live in `../fixtures/`; technical conclusions and curated evidence live
in `../traces/`. The manifest connects each test to those inputs and declares
its expected outputs.

## Manifest fields

Each entry in `manifest.json` has:

- a stable `id`, title, script, and test kind;
- suite membership and an approximate runtime;
- ROM and host-tool requirements;
- tracked fixtures or explicitly external inputs; and
- required output filenames or glob patterns.

The kinds are:

- `atomic`: one distinct test, eligible for suite expansion;
- `alias`: an old command retained for compatibility; and
- `aggregate`: a legacy script that calls several atomic tests.

Aliases resolve to their canonical test when selected through the runner. A
pure aggregate may declare `members`; selecting it runs those atomic members
through separate result directories instead of allowing their evidence files
to overwrite one another. The runner checks that every top-level `tests/*.sh`
file is represented in the manifest and that every manifest script exists.
Adding or removing a test therefore requires updating the catalog in the same
change.

## DC323 command coverage

`dc323-command-catalog.json` is the canonical inventory of implemented,
partial, no-op, and unsupported command families. Tests declare only the
families whose behavior they actually assert using a `dc323_commands` list;
individual external-corpus cases make the same declaration in
`vt340test-cases.json`.

`dc323-command-coverage.sh` validates those declarations and the required
coverage strength, then checks the generated `dc323-command-coverage.md`
matrix. Moving a family from unsupported to partial or implemented therefore
requires appropriate direct or integration coverage in the same change. A
command merely present during boot is `observed`, not functional coverage.

Regenerate the human-readable matrix after editing command status or claims:

```sh
python3 vt340-research/tests/lib/dc323_coverage.py --write
vt340-research/tests/dc323-command-coverage.sh
```

## Principal suites

| Suite | Purpose |
| --- | --- |
| `quick` | Short structural, ROM, smoke, and firmware-free checks |
| `core` | Main confidence set used after emulator changes |
| `device` | Firmware-free DC323 device tests |
| `startup` | Boot, POST, mailbox, and processor synchronization |
| `graphics` | Raster, Set-Up, color, and SIXEL behavior |
| `conformance` | Selected programs from the external `vt340test` behavior corpus |
| `gallery` | Tracked screenshots, animations, and provenance checks |
| `serial` | UART diagnostics, connectors, and PTY transport |
| `persistence` | E80 configuration persistence |
| `historical` | Sprint-specific evidence that remains reproducible |
| `all` | Every atomic test exactly once |

## Requirements and isolation

The standalone DC323 device tests do not require VT340 firmware. DC7051
compatibility timing is driver-local and covered by the VT340 integration
tests. Integration tests require the private ROM set described in
`../roms/catalog.json` and `../BUILDING.md`. Use
`../tools/rom_catalog.py verify --location active` to validate the selected
MAME profile before a long suite.

PTY and SIXEL tests require normal host pseudo-terminal support. Individual
tests additionally declare tools such as `jq`, `rg`, Python, Perl, and `make`;
the common runner checks these before starting. Configuration, NVRAM, save
states, and intermediate streams use isolated temporary directories and do not
modify the developer's normal MAME state.

The `conformance` suite additionally expects the upstream `vt340test` checkout
at `../sources/vt340test` relative to the MAME checkout. Its selected source
revision and individual file hashes are pinned in `vt340test-cases.json`, so
unrelated edits in that checkout do not silently change a regression. See
`vt340test-coverage.md` for the reviewed inventory, current coverage, and the
groups that still need bidirectional or interactive test support.

The curated visual showcase lives in `../gallery/README.md`. Its `gallery`
suite verifies that every tracked PNG/GIF is declared, linked, dimensionally
valid, and byte-identical to its recorded provenance hash.
