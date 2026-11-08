#!/usr/bin/env python3
"""Serve the browser build and bridge or replay raw serial byte streams."""

import argparse
import asyncio
import contextlib
import fcntl
import os
from pathlib import Path
import pty
import secrets
import signal
import struct
import termios

from aiohttp import WSMsgType, web

XON = 0x11
XOFF = 0x13


async def serial(request):
    """Bridge one authenticated binary WebSocket connection to a byte source."""
    if request.query.get("token") != request.app["token"]:
        raise web.HTTPForbidden(text="A valid session token is required")

    origin = request.headers.get("Origin")
    if origin and origin != f"{request.scheme}://{request.host}":
        raise web.HTTPForbidden(text="Origin mismatch")

    websocket = web.WebSocketResponse(protocols=("binary",), max_msg_size=65536)
    await websocket.prepare(request)
    replay_path = request.app.get("replay_path")
    capture_rx_path = request.app.get("capture_rx_path")
    capture_tx_path = request.app.get("capture_tx_path")
    capture_rx = open(capture_rx_path, "wb") if capture_rx_path else None
    capture_tx = open(capture_tx_path, "wb") if capture_tx_path else None
    flow_enabled = request.app["xon_xoff"]
    output_enabled = asyncio.Event()
    output_enabled.set()

    async def handle_terminal_bytes(data):
        if capture_tx:
            capture_tx.write(data)
            capture_tx.flush()
        if not flow_enabled:
            return data

        filtered = bytearray()
        for byte in data:
            if byte == XOFF:
                output_enabled.clear()
            elif byte == XON:
                output_enabled.set()
            else:
                filtered.append(byte)
        return filtered

    if replay_path:
        async def replay_output():
            await asyncio.sleep(request.app["replay_start_delay"])
            with open(replay_path, "rb") as source:
                while data := source.read(request.app["replay_chunk_size"]):
                    await output_enabled.wait()
                    await websocket.send_bytes(data)
                    await asyncio.sleep(request.app["replay_chunk_delay"])
            await websocket.close()

        output_task = asyncio.create_task(replay_output())
        try:
            async for message in websocket:
                if message.type == WSMsgType.BINARY:
                    await handle_terminal_bytes(message.data)
                elif message.type == WSMsgType.TEXT:
                    await websocket.close(
                        code=1003, message=b"Binary serial data required"
                    )
        finally:
            output_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, OSError):
                await output_task
            if capture_rx:
                capture_rx.close()
            if capture_tx:
                capture_tx.close()
        return websocket

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

    def child_setup():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    environment = dict(os.environ, TERM="vt340")
    try:
        process = await asyncio.create_subprocess_exec(
            *request.app["command"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=environment,
            preexec_fn=child_setup,
        )
    except Exception:
        os.close(master)
        os.close(slave)
        await websocket.close(code=1011, message=b"Could not start PTY command")
        return websocket

    os.close(slave)
    os.set_blocking(master, False)
    loop = asyncio.get_running_loop()

    async def forward_pty_output():
        while True:
            await output_enabled.wait()
            ready = loop.create_future()
            loop.add_reader(
                master, lambda: None if ready.done() else ready.set_result(None)
            )
            try:
                await ready
                try:
                    data = os.read(master, 4096)
                except BlockingIOError:
                    continue
                except OSError:
                    break
                if not data:
                    break
                if capture_rx:
                    capture_rx.write(data)
                    capture_rx.flush()
                await output_enabled.wait()
                await websocket.send_bytes(data)
            finally:
                loop.remove_reader(master)
        await websocket.close()

    output_task = asyncio.create_task(forward_pty_output())
    try:
        async for message in websocket:
            if message.type == WSMsgType.BINARY:
                data = await handle_terminal_bytes(message.data)
                remaining = memoryview(data)
                while remaining:
                    try:
                        count = os.write(master, remaining)
                    except BlockingIOError:
                        await asyncio.sleep(0.005)
                        continue
                    remaining = remaining[count:]
            elif message.type == WSMsgType.TEXT:
                await websocket.close(
                    code=1003, message=b"Binary serial data required"
                )
    finally:
        output_task.cancel()
        with contextlib.suppress(asyncio.CancelledError, OSError):
            await output_task
        os.close(master)
        if capture_rx:
            capture_rx.close()
        if capture_tx:
            capture_tx.close()
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(process.pid, signal.SIGHUP)
        try:
            await asyncio.wait_for(process.wait(), 2)
        except asyncio.TimeoutError:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(process.pid, signal.SIGKILL)
            await process.wait()

    return websocket


async def session(request):
    """Provide a same-origin client with the ephemeral serial endpoint."""
    if request.headers.get("Sec-Fetch-Site") == "cross-site":
        raise web.HTTPForbidden()
    endpoint = f"/serial?token={request.app['token']}"
    return web.json_response(
        {"endpoint": endpoint}, headers={"Cache-Control": "no-store"}
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--root", type=Path, default=Path(__file__).parent / "dist")
    parser.add_argument(
        "--capture-rx",
        type=Path,
        help="write host-to-terminal bytes to this file (overwritten per connection)",
    )
    parser.add_argument(
        "--capture-tx",
        type=Path,
        help="write terminal-to-host bytes, including XON/XOFF, to this file",
    )
    parser.add_argument(
        "--replay",
        type=Path,
        help="replay a captured host-to-terminal stream instead of starting a command",
    )
    parser.add_argument("--replay-start-delay", type=float, default=0.5)
    parser.add_argument("--replay-chunk-size", type=int, default=4096)
    parser.add_argument("--replay-chunk-delay", type=float, default=0.01)
    parser.add_argument(
        "--no-xon-xoff",
        action="store_false",
        dest="xon_xoff",
        help="pass XON/XOFF through as data instead of applying software flow control",
    )
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="-- /bin/zsh -l OR -- ssh -tt user@host",
    )
    args = parser.parse_args()

    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if args.replay and command:
        parser.error("--replay cannot be combined with a command")
    if args.replay_chunk_size <= 0:
        parser.error("--replay-chunk-size must be positive")
    if args.replay_start_delay < 0 or args.replay_chunk_delay < 0:
        parser.error("replay delays cannot be negative")

    app = web.Application()
    app["token"] = secrets.token_urlsafe(32)
    app["command"] = command or [os.environ.get("SHELL", "/bin/sh"), "-l"]
    app["xon_xoff"] = args.xon_xoff
    app["capture_rx_path"] = args.capture_rx
    app["capture_tx_path"] = args.capture_tx
    app["replay_path"] = args.replay
    app["replay_start_delay"] = args.replay_start_delay
    app["replay_chunk_size"] = args.replay_chunk_size
    app["replay_chunk_delay"] = args.replay_chunk_delay
    app.router.add_get("/serial", serial)
    app.router.add_get("/session", session)
    app.router.add_get("/", lambda request: web.FileResponse(args.root / "index.html"))
    app.router.add_static("/", args.root, show_index=False)
    web.run_app(app, host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
