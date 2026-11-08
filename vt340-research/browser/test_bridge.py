#!/usr/bin/env python3
"""Exercise bridge authorization, raw bytes, and XON/XOFF flow control."""

import asyncio
import importlib.util
from pathlib import Path
import secrets
import tempfile

from aiohttp import ClientSession, web


BRIDGE_PATH = Path(__file__).with_name("bridge.py")
SPEC = importlib.util.spec_from_file_location("vt340_browser_bridge", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


async def start_app(*, xon_xoff, capture_rx=None, capture_tx=None, replay=None):
    app = web.Application()
    app["token"] = secrets.token_urlsafe(32)
    app["xon_xoff"] = xon_xoff
    app["capture_rx_path"] = capture_rx
    app["capture_tx_path"] = capture_tx
    app["replay_path"] = replay
    app["replay_start_delay"] = 0
    app["replay_chunk_size"] = 17
    app["replay_chunk_delay"] = 0
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
    return app, runner, f"http://127.0.0.1:{port}/serial"


async def test_raw_bytes():
    app, runner, url = await start_app(xon_xoff=False)

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


async def test_flow_control():
    app, runner, url = await start_app(xon_xoff=True)
    try:
        async with ClientSession() as client:
            async with client.ws_connect(
                f"{url}?token={app['token']}", protocols=["binary"]
            ) as websocket:
                assert (await websocket.receive(timeout=5)).data == b"READY"
                await websocket.send_bytes(bytes([bridge.XOFF]))
                await websocket.send_bytes(b"A")
                try:
                    await websocket.receive(timeout=0.25)
                except asyncio.TimeoutError:
                    pass
                else:
                    raise AssertionError("PTY output continued after XOFF")

                await websocket.send_bytes(bytes([bridge.XON]))
                assert (await websocket.receive(timeout=5)).data == b"A"
    finally:
        await runner.cleanup()


async def test_capture_and_replay():
    with tempfile.TemporaryDirectory() as directory:
        capture_rx = Path(directory) / "host-to-terminal.bin"
        capture_tx = Path(directory) / "terminal-to-host.bin"
        app, runner, url = await start_app(
            xon_xoff=False,
            capture_rx=capture_rx,
            capture_tx=capture_tx,
        )
        payload = bytes(range(256))
        try:
            async with ClientSession() as client:
                async with client.ws_connect(
                    f"{url}?token={app['token']}", protocols=["binary"]
                ) as websocket:
                    assert (await websocket.receive(timeout=5)).data == b"READY"
                    await websocket.send_bytes(payload)
                    received = b""
                    while len(received) < len(payload):
                        received += (await websocket.receive(timeout=5)).data
                    assert received == payload
        finally:
            await runner.cleanup()

        assert capture_rx.read_bytes() == b"READY" + payload
        assert capture_tx.read_bytes() == payload

        app, runner, url = await start_app(
            xon_xoff=True,
            replay=capture_rx,
        )
        try:
            async with ClientSession() as client:
                async with client.ws_connect(
                    f"{url}?token={app['token']}", protocols=["binary"]
                ) as websocket:
                    received = b""
                    while len(received) < len(b"READY" + payload):
                        message = await websocket.receive(timeout=5)
                        if message.type == bridge.WSMsgType.BINARY:
                            received += message.data
                    assert received == b"READY" + payload
        finally:
            await runner.cleanup()


async def test():
    await test_raw_bytes()
    await test_flow_control()
    await test_capture_and_replay()
    print("PASS: authorization, raw bytes, flow control, capture, and replay")


if __name__ == "__main__":
    asyncio.run(test())
