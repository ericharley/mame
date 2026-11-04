#!/usr/bin/env python3
"""Run the VT340 browser integration test against a bridge on port 8080."""

import asyncio
from pathlib import Path

from playwright.async_api import async_playwright


async def main():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            headless=True, args=["--autoplay-policy=no-user-gesture-required"]
        )
        page = await browser.new_page(viewport={"width": 1440, "height": 1100})
        page.on(
            "console",
            lambda message: print(
                "CONSOLE", message.type, message.text[:500], flush=True
            ),
        )
        page.on("pageerror", lambda error: print("PAGEERROR", error, flush=True))

        await page.goto("http://127.0.0.1:8080")
        await page.wait_for_function(
            "!document.getElementById('start').disabled", timeout=120000
        )
        print("READY", flush=True)
        await page.evaluate(
            """
            window.txBytes = [];
            window.rxCount = 0;
            const originalOutput = Module.serialOutput;
            Module.serialOutput = byte => {
                txBytes.push([typeof byte, String(byte)]);
                originalOutput(byte);
            };
            const originalInput = Module.serialInput;
            Module.serialInput = (pointer, length) => {
                const count = originalInput(pointer, length);
                rxCount += count;
                return count;
            };
            """
        )
        await page.select_option("#scale", "1")
        await page.click("#start")
        await page.wait_for_timeout(45000)
        print("STATUS", await page.locator("#status").inner_text(), flush=True)
        print("LOG", await page.locator("#log").inner_text(), flush=True)
        await page.screenshot(path=str(Path("/tmp/vt340-browser.png")))

        await page.click("#connect")
        await page.wait_for_timeout(3000)
        print("CONNECTED", await page.locator("#status").inner_text(), flush=True)
        await page.locator("#canvas").click()
        for key in ("e", "c", "h", "o", "Space", "o", "k", "Enter"):
            await page.keyboard.down(key)
            await page.wait_for_timeout(400)
            await page.keyboard.up(key)
            await page.wait_for_timeout(200)
        await page.wait_for_timeout(3000)
        await page.screenshot(path="/tmp/vt340-browser-connected.png")

        await page.evaluate(
            "FS.writeFile('/persist/persistence-check', new Uint8Array([34, 0, 255]))"
        )
        await page.click("#save")
        await page.wait_for_timeout(3000)
        transmitted = await page.evaluate("txBytes")
        print("TXBYTES", transmitted, "RXCOUNT", await page.evaluate("rxCount"), flush=True)
        print("SAVE", await page.locator("#status").inner_text(), flush=True)
        print(
            "NVRAM",
            await page.evaluate("FS.readFile('/persist/nvram/vt340/eeprom').length"),
            flush=True,
        )
        assert await page.evaluate("rxCount") > 0
        text = "".join(
            chr(int(value)) for kind, value in transmitted if kind == "number"
        )
        assert "echo ok\r" in text

        await page.reload()
        await page.wait_for_function(
            "!document.getElementById('start').disabled", timeout=120000
        )
        persisted = await page.evaluate(
            "Array.from(FS.readFile('/persist/persistence-check'))"
        )
        assert persisted == [34, 0, 255]
        print("PERSISTENCE PASS", flush=True)
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
