#!/usr/bin/env python3
"""Serve the browser build and bridge raw binary WebSocket data to a PTY."""

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


async def serial(request):
    """Bridge one authenticated binary WebSocket connection to a child PTY."""
    if request.query.get("token") != request.app["token"]:
        raise web.HTTPForbidden(text="A valid session token is required")

    origin = request.headers.get("Origin")
    if origin and origin != f"{request.scheme}://{request.host}":
        raise web.HTTPForbidden(text="Origin mismatch")

    websocket = web.WebSocketResponse(protocols=("binary",), max_msg_size=65536)
    await websocket.prepare(request)
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
                await websocket.send_bytes(data)
            finally:
                loop.remove_reader(master)
        await websocket.close()

    output_task = asyncio.create_task(forward_pty_output())
    try:
        async for message in websocket:
            if message.type == WSMsgType.BINARY:
                remaining = memoryview(message.data)
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
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGHUP)
        try:
            await asyncio.wait_for(process.wait(), 2)
        except asyncio.TimeoutError:
            with contextlib.suppress(ProcessLookupError):
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
        "command",
        nargs=argparse.REMAINDER,
        help="-- /bin/zsh -l OR -- ssh -tt user@host",
    )
    args = parser.parse_args()

    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]

    app = web.Application()
    app["token"] = secrets.token_urlsafe(32)
    app["command"] = command or [os.environ.get("SHELL", "/bin/sh"), "-l"]
    app.router.add_get("/serial", serial)
    app.router.add_get("/session", session)
    app.router.add_get("/", lambda request: web.FileResponse(args.root / "index.html"))
    app.router.add_static("/", args.root, show_index=False)
    web.run_app(app, host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
