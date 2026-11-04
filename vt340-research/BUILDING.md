# Building and inspecting the first-stage driver

From the MAME checkout root:

```sh
PATH="/opt/homebrew/bin:$PATH" make -j4 REGENIE=1 USE_LIBSDL=1 \
  SUBTARGET=vt340 \
  SOURCES=src/mame/dec/vt340.cpp,src/mame/dec/lk201.cpp \
  MACHINES='68681,SCN_PCI,EEPROMDEV'
./vt340 -listfull vt340
./vt340 -verifyroms vt340 -rompath roms
./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1
```

The full LK201 device requires `roms/lk201.zip`. The expected files and SHA-1
values are `23-001s9-00.bin` (`a11ae004d2d6055d7279da3560c3e56610a19fdb`)
and `23-004m2.8051h.e1` (`9744c561d76fe85afaccc7a2485ce2865236873a`).
ROM archives remain local and ignored by Git.

E80 is backed by MAME's X2804 device. Its recovered ROM image supplies the
factory default on the first run, and later firmware writes are stored in the
configured NVRAM directory. Use the Set-Up Directory's **Save Current
Settings** action before exiting when settings have been changed.

`REGENIE=1` is needed for the first targeted build after adding the driver to
`src/mame/mame.lst`; it may be omitted for incremental builds.  The tested
macOS setup uses Homebrew `sdl3` and `pkgconf`.  A shallow MAME checkout may
print `fatal: No names found, cannot describe anything.` while deriving its
version; this did not prevent a successful build.

For external bus and port tracing, temporarily set `VERBOSE` in `vt340.cpp`
to `LOG_PORTS | LOG_XDATA`, rebuild, and preserve `error.log`.  This is a
compile-time trace control and does not modify the emulated responses.

Debugger launch:

```sh
./vt340 vt340 -rompath roms -debug -window
```

Useful first breakpoints are CPU1 `0238` and CPU2 `0212`.  Do not treat raw
instruction count as boot success; inspect the first repeated polling loop or
unimplemented XDATA dependency.

Two debugger-enabled Lua scripts preserve the CPU1 bad-path investigation:

```sh
./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1 \
  -debug -debugger none -autoboot_delay 0 \
  -autoboot_script vt340-research/traces/cpu1-branch-debug.lua -debuglog

./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1 \
  -debug -debugger none -autoboot_delay 0 \
  -autoboot_script vt340-research/traces/cpu1-execution-trace.lua
```

The first logs bounded register snapshots at CPU1 `09e4`; the second writes
`cpu1-execution.tr`.  Both generated logs remain unversioned.

`traces/cpu2-execution-trace.lua` similarly writes `cpu2-execution.tr` for
localizing the current graphics-initialization loop.  Trace files can grow
quickly; always use a bounded run and keep generated output unversioned.

The ROM files live in `roms/vt340/` and remain ignored by Git.  Their verified
digests and source URLs are recorded in `firmware/manifest.json`.

### Scaled, smoothed display

From the MAME checkout root:

```sh
./vt340-research/tools/vt340-display 2 smooth
./vt340-research/tools/vt340-display 4 smooth
./vt340-research/tools/vt340-display 2 sharp
```

The launcher defaults to 2× prescaling and bilinear smoothing, using OpenGL.
Prescaling expands the native framebuffer in both axes before filtering;
4× uses four times the texture memory of 2×. Resize the window to choose the
final display size. This does not add detail to the emulated framebuffer.
`sharp` disables smoothing. Extra MAME options may follow the display mode.
