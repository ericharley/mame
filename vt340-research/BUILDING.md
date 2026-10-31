# Building and inspecting the first-stage driver

From the MAME checkout root:

```sh
PATH="/opt/homebrew/bin:$PATH" make -j4 REGENIE=1 USE_LIBSDL=1 \
  SUBTARGET=vt340 SOURCES=src/mame/dec/vt340.cpp MACHINES='68681,SCN_PCI'
./vt340 -listfull vt340
./vt340 -verifyroms vt340 -rompath roms
./vt340 vt340 -rompath roms -video none -sound none -seconds_to_run 1
```

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
