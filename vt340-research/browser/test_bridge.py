#!/usr/bin/env python3
"""Exercise bridge authorization and all byte values through a raw PTY."""

import asyncio
import importlib.util
from pathlib import Path
import secrets

from aiohttp import ClientSession, web


BRIDGE_PATH = Path(__file__).with_name("bridge.py")
SPEC = importlib.util.spec_from_file_location("vt340_browser_bridge", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


async def test():
    app = web.Application()
    app["token"] = secrets.token_urlsafe(32)
    app["command"] = [
        "/bin/sh",
        "-c",
        "stty raw -echo; printf READY; cat",
    ]
    app.router.add_get("/serial", bridge.serial)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]
    url = f"http://127.0.0.1:{port}/serial"

    try:
        async with ClientSession() as client:
            async with client.get(url) as response:
                assert response.status == 403
            async with client.get(
                f"{url}?token={app['token']}",
                headers={"Origin": "https://bad.example"},
            ) as response:
                assert response.status == 403

            async with client.ws_connect(
                f"{url}?token={app['token']}", protocols=["binary"]
            ) as websocket:
                assert (await websocket.receive(timeout=5)).data == b"READY"
                payload = bytes(range(256))
                await websocket.send_bytes(payload)
                received = b""
                while len(received) < len(payload):
                    received += (await websocket.receive(timeout=5)).data
                assert received == payload
    finally:
        await runner.cleanup()

    print("PASS: authorization, origin, and all 256 byte values through a PTY")


if __name__ == "__main__":
    asyncio.run(test())
