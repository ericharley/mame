# Building and inspecting the VT340 research driver

## Prerequisites

Use the normal MAME build prerequisites for the host platform. The targeted
macOS build used Homebrew SDL 3 and `pkgconf`; if Homebrew is installed under
`/opt/homebrew`, place that directory on `PATH` before building:

```sh
export PATH="/opt/homebrew/bin:$PATH"
```

The build itself does not depend on that absolute path. Set `JOBS` to choose
the desired parallelism.

From the MAME checkout root:

```sh
make -j"${JOBS:-4}" REGENIE=1 USE_LIBSDL=1 \
  SUBTARGET=vt340 \
  SOURCES=src/mame/dec/vt340.cpp,src/mame/dec/lk201.cpp \
  MACHINES='68681,SCN_PCI,EEPROMDEV'
./vt340 -listfull vt340
./vt340 -verifyroms vt340 -rompath roms
./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1
```

The tracked ROM catalog is under `vt340-research/roms/`; copyrighted images
remain local and ignored by Git. The current working profile combines the
VT330/VT340 V1.1 research set with the LK201 MAME reference set. Import an
existing MAME layout and verify both copies with:

```sh
vt340-research/tools/rom_catalog.py import-current
vt340-research/tools/rom_catalog.py verify
vt340-research/tools/rom_catalog.py verify --location active
```

The versioned local copies live under `roms/library/`. To restore the standard
MAME layout from that library:

```sh
vt340-research/tools/rom_catalog.py activate vt340-v1.1-working
```

Activation creates `roms/vt340/` and `roms/lk201.zip`; other MAME ROM sets are
untouched. Exact component names, sizes, hashes, provenance, and the distinction
between the later 6805 and earlier 8051H LK201 images are recorded in the set
manifests. See `roms/README.md` before adding another firmware version.

E80 is backed by MAME's X2804 device. Its recovered ROM image supplies the
factory default on the first run, and later firmware writes are stored in the
configured NVRAM directory. Use the Set-Up Directory's **Save Current
Settings** action before exiting when settings have been changed.

`REGENIE=1` is needed for the first targeted build after adding the driver to
`src/mame/mame.lst`; it may be omitted for incremental builds.  The tested
macOS setup uses Homebrew `sdl3` and `pkgconf`.  A shallow MAME checkout may
print `fatal: No names found, cannot describe anything.` while deriving its
version; this did not prevent a successful build.

## Startup modes

The default configuration preserves the original ROM and its approximately
120-second timeout fallback. To exercise the optional fast-start configuration
without changing the normal user configuration or NVRAM, run:

```sh
vt340-research/tests/fast-start.sh ./vt340
```

The patch changes one ROM operand at reset and recomputes the firmware checksum.
The later native result wait and success validation remain active. Its exact
scope and limitations are documented in `firmware/fast-start-patch.md`.

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

The active ROM files live in `roms/vt340/` and remain ignored by Git. Their
versioned local sources live under `roms/library/`; verified digests and source
URLs are recorded in `roms/sets/`.

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
