# VT340 in a browser

This experimental frontend runs the VT340 MAME target in WebAssembly and
bridges its serial port to a local PTY over an authenticated, same-origin
WebSocket. It is a development preview, not an internet-facing terminal
service.

The generated `dist/` directory and `vt340-browser.zip` contain VT340/LK201
ROMs and the current 512-byte EEPROM snapshot. They are ignored by Git and must
remain private. MAME's license is copied into the package; source modifications
remain in the accompanying checkout.

## Run

```sh
./run.sh
```

Open <http://127.0.0.1:8080>, select **Start terminal**, then **Connect**.
The bridge creates a shell in a PTY. It listens on loopback only, validates
browser origins, and requires a fresh session token. Each connection starts its
own process; disconnecting ends that process.

For SSH, run the bridge with a fixed SSH destination:

```sh
./run.sh -- ssh -tt user@server
```

SSH runs on the bridge host using its normal keys, agent and known-host checks.
Password and host-key prompts appear in the emulated terminal. The browser
transports serial bytes over WebSocket; it does not open a raw TCP SSH connection.
Do not expose the development bridge directly to another network. For remote
access, place it behind an authenticated HTTPS/WSS reverse proxy and review
its bind address, forwarded-header, and origin policy deliberately.

A different raw binary WebSocket endpoint can be entered in the page. The
protocol is unframed serial bytes in binary WebSocket messages, with the `binary`
subprotocol. It is not Telnet, Socket.IO, or an SSH wire protocol. Software
flow control is enabled by default: the frontend immediately pauses queued
host data on XOFF and resumes it on XON, while the bridge applies the same
state to PTY output and consumes those two control bytes. Use
`--no-xon-xoff` only when all 256 byte values must pass through as application
data.

## Capture and replay

Capture the exact byte stream in both directions while running a command:

```sh
./run.sh \
  --capture-rx /tmp/vt340-host-to-terminal.bin \
  --capture-tx /tmp/vt340-terminal-to-host.bin \
  -- ssh -tt user@server
```

`--capture-rx` records host-to-terminal data before it enters the browser.
`--capture-tx` records terminal-to-host data, including XON and XOFF. Each file
is overwritten when a new browser serial connection opens.

Replay a captured receive stream without starting a PTY command:

```sh
./run.sh --replay /tmp/vt340-host-to-terminal.bin
```

Replay uses the same authenticated WebSocket path and honors XON/XOFF. The
start delay, chunk size, and inter-chunk delay can be adjusted with
`--replay-start-delay`, `--replay-chunk-size`, and `--replay-chunk-delay`.

## Terminal settings and persistence

The package carries the current keyboard configuration alongside the EEPROM
seed. The browser serial adapter uses the VT340 driver defaults: 19200 baud,
8 data bits, no parity, one stop bit, with XON/XOFF handled by the frontend and
bridge.
Set the terminal's communications settings to match in Set-Up. In the VT340
Set-Up Directory, use Save Current Settings. Then click Save settings in the
page; this stops the emulator, flushes MAME's EEPROM/configuration files and
copies them to this browser's IndexedDB storage. Reload to restart.
Closing a tab without this step can lose recent settings. Storage is specific
to the browser profile and web origin, and may be cleared by the browser.
The packaged EEPROM seeds a new browser only; existing settings take precedence.

The scale control sets MAME prescaling at startup; smoothing also controls CSS
sampling when the canvas is resized. Upscaling does not add framebuffer detail.

## Rebuild

Activate Emscripten 6.0.2 or later, then run `./build.sh` from this directory.
The script builds the targeted VT340 runtime and assembles `dist/` and
`vt340-browser.zip`. ROMs are copied from the checkout's `roms/`; the EEPROM
seed comes from `nvram/vt340/eeprom`. The current `cfg/vt340.cfg` supplies the
keyboard/input seed after native serial endpoint selections are removed. Build
dependencies are downloaded by Emscripten.

## Validation

Run the bridge-only regression with:

```sh
.venv/bin/python test_bridge.py
```

For the browser integration test, install Playwright and Chromium in the local
virtual environment, leave `./run.sh` active on port 8080, and run:

```sh
.venv/bin/python -m pip install playwright
.venv/bin/python -m playwright install chromium
.venv/bin/python test_browser.py
```

The current build was tested in Chromium with a local PTY shell: firmware boot, keyboard-generated
`echo ok` and its visible reply, incoming serial data, EEPROM flush, and browser
storage surviving a reload. `test_bridge.py` checks all 256 byte values through
a raw PTY with flow control disabled, verifies XOFF pause/XON resume with flow
control enabled, verifies byte-exact capture/replay, and rejects invalid
tokens/origins. `test_browser.py` additionally
requires Playwright/Chromium and the bridge running on port 8080.
SSH forwarding is provided through the system SSH client; a remote login has
not been tested because no destination was supplied.

The measured runtime is approximately 21 MiB uncompressed; the complete ZIP is
about 4.9 MiB. Exact sizes vary with the compiler. The local bridge stays on
`127.0.0.1` by default.
