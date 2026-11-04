# `vt340test` corpus review and regression coverage

## Source and policy

The reviewed source is the external
[`hackerb9/vt340test`](https://github.com/hackerb9/vt340test) checkout at
`../sources/vt340test`, revision
`9485704b827ec6d40109d1955e9e6c6a485a50c2`.

This repository does not copy or rewrite that collection. The executable
regression catalog in `vt340test-cases.json` pins both the source revision and
the SHA-256 of every invoked source file. This allows the external checkout to
contain unrelated local work without silently changing a test. At review time,
the only local modification in that checkout was `sixeltests/animation.sh`; it
is not part of the automated selection.

The corpus contains more than a thousand files. Many are reference images,
VMS command procedures, captured results, emulator-specific notes, or tests
that require terminal replies or physical input. They are useful evidence, but
they are not automatically treated as passing MAME regressions.

## Automated selection

Run the selection from the MAME checkout root:

```sh
vt340-research/tests/run.py run conformance --binary ./vt340
```

The suite starts a fresh VT340 and isolated NVRAM/configuration for each case,
generates the original program's byte stream with `TERM=vt340`, sends it over
the emulated Comm 1 PTY at a controlled rate, and checks:

- the invoked source file's SHA-256;
- generated wire-stream length;
- exact bytes received by the firmware, with no omissions or substitutions;
- execution of the DC323 command families claimed by that individual case;
- a deterministic visible-framebuffer hash and whole-bitmap nonzero-pixel count; and
- production of a screenshot and structured event trace.

Color-sensitive cases may additionally pin the rendered PNG SHA-256. The RAF
case uses this to distinguish its intended red/white/blue palette from the
same correct bitmap indices displayed through a monochrome palette.

The harness appends the six-byte DECTCEM “cursor off” control after each
unmodified source stream. The suffix is included in the wire-byte assertion.
It removes the periodic 8-by-16 cursor overlay from framebuffer hashes without
changing the tested program or graphics operation; otherwise host completion
time can select either cursor-blink phase.

| Case | Original program | Functional coverage |
| --- | --- | --- |
| `regis-raf` | `regis/registest.sh raf` | ReGIS circles, color-index selection, nested fill |
| `regis-grid` | `regis/registest.sh grid` | ReGIS vectors, patterned lines, rotated text, coordinates |
| `sixel-repeat` | `j4james/repeat_introducer.sh` | SIXEL repeat introducer, omitted/zero counts, clipping |
| `sixel-raster-size` | `j4james/raster_dimensions.sh` | DECGRA raster dimensions, omitted/zero dimensions |
| `sixel-overlap` | `j4james/image_overlap.sh` | Transparent background, palette selection, image layering |
| `sixel-editing` | `j4james/image_movement.sh` | Bitmap response to insert/delete line and character |
| `sixel-scrolling` | `j4james/scrolling.sh` | SIXEL scrolling, margins, graphic newline |
| `sixel-line-attributes` | `j4james/line_attributes.sh` | DECDWL/DECDHL interaction, text backing store, erasure |

The common runner preserves each input stream, MAME log, JSON event trace, and
PNG under the test result's `artifacts/<case>/` directory. Its generated report
therefore acts as a visual gallery as well as a binary regression result.

## Reviewed material not yet automated

The remaining material falls into harness or device-model groups rather than a
single flat backlog.

### Bidirectional terminal reports

Mode-report, status-report, cursor-report, palette-query, and related scripts
need a host-side reader that validates replies from the terminal while it sends
requests. Representative material includes `checkmode`, `testdecsdm.sh`,
`dsr_multiple.sh`, and color-map query tests. This is the best next harness
extension because it can cover many small tests without changing emulation.

### Text pages, viewports, and editing

Off-screen page memory, page flipping, viewport movement, cursor behavior,
trailing graphic-newline handling, and additional scrolling cases can reuse the
current PTY/framebuffer harness. They need stable end states selected from the
source collection and, where appropriate, checks of more than one capture time.

### Additional SIXEL and ReGIS graphics

The collection includes SIXEL background selection, macro aspect ratio,
margin clipping, P2 behavior, palette selection, off-screen drawing, page
flipping, and DEC double-width quirks. ReGIS includes bit-plane, plaid,
checkerboard, text, InterConnections, and animated ODE examples. Some are
immediately streamable; others contain pauses, prompts, or animation and need
case-specific capture points rather than one final hash.

### Downloadable characters and character sets

The large `charset`/DRCS collection exercises GL/GR selection, national
replacement sets, soft-font download, and glyph rendering. Useful regressions
will need encoding-aware input generation and framebuffer-region checks so a
correct glyph is distinguished from merely receiving the stream.

### Media copy and printer paths

Media-copy tests send terminal-generated SIXEL or other output back to the
host/printer. They require bidirectional capture, printer Set-Up state, and
longer runs. They should be a separate suite from display-input graphics.

### Locator and physical input

Locator tests depend on VSXXX mouse/tablet events and terminal locator reports.
They cannot be meaningful until the corresponding input device path is modeled
and the harness can inject deterministic coordinates and button transitions.

### Tektronix, Kermit, VMS, and reference results

Tektronix and Kermit demos require explicit mode/setup assumptions and curated
capture points. VMS command procedures may need a compatible host environment
or conversion into byte-stream fixtures. Reference screenshots and documented
results should be used as review evidence, not executed or declared passing by
filename alone.

## Baseline maintenance

`VT340_UPDATE_BASELINE=1` permits a controlled run to print new framebuffer
values, but it never disables source-hash, byte-count, UART-integrity, graphics-
activity, or screenshot checks. Review the generated gallery before changing
`vt340test-cases.json`; a new hash is evidence of changed output, not proof that
the output is correct.
