#!/usr/bin/env python3
"""Assemble the private browser runtime, ROMs, and initial NVRAM package."""

import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DIST = HERE / "dist"
ASSETS = DIST / "assets"


def add_asset(manifest, source, target, *, seed=False):
    """Copy one runtime asset and append its virtual-filesystem metadata."""
    relative = target.lstrip("/")
    destination = ASSETS / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    manifest.append({"file": relative, "path": target, "seed": seed})


def make_seed_config():
    """Keep user input settings while removing native endpoint selections."""
    tree = ET.parse(ROOT / "cfg/vt340.cfg")
    system = tree.getroot().find("system")
    if system is None:
        raise RuntimeError("cfg/vt340.cfg has no system element")

    for child in list(system):
        if child.tag != "input":
            system.remove(child)

    inputs = system.find("input")
    if inputs is None:
        raise RuntimeError("cfg/vt340.cfg has no input element")
    for port in list(inputs):
        tag = port.get("tag", "")
        if any(device in tag for device in (":pty:", ":null_modem:")):
            inputs.remove(port)

    destination = ASSETS / "seed-vt340.cfg"
    tree.write(destination, encoding="utf-8", xml_declaration=True)
    return destination


def main():
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    ASSETS.mkdir(exist_ok=True)

    for name in ("index.html", "frontend.js"):
        shutil.copy2(HERE / name, DIST / name)
    for name in ("vt340web.js", "vt340web.wasm"):
        shutil.copy2(ROOT / name, DIST / name)

    manifest = []
    for rom in sorted((ROOT / "roms/vt340").iterdir()):
        if rom.is_file():
            add_asset(manifest, rom, f"/roms/vt340/{rom.name}")
    add_asset(manifest, ROOT / "roms/lk201.zip", "/roms/lk201.zip")
    add_asset(
        manifest,
        ROOT / "nvram/vt340/eeprom",
        "/persist/nvram/vt340/eeprom",
        seed=True,
    )

    config = make_seed_config()
    manifest.append(
        {"file": config.name, "path": "/persist/cfg/vt340.cfg", "seed": True}
    )
    (ASSETS / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    shutil.copy2(ROOT / "COPYING", DIST / "MAME-COPYING")

    archive = HERE / "vt340-browser.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
        for path in DIST.rglob("*"):
            if path.is_file():
                member = Path("vt340-browser/dist") / path.relative_to(DIST)
                output.write(path, member)
        for name in ("bridge.py", "requirements.txt", "README.md", "run.sh"):
            output.write(HERE / name, f"vt340-browser/{name}")

    print(archive)


if __name__ == "__main__":
    main()
