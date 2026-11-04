#!/usr/bin/env python3
"""Manage the local, versioned ROM library described by the VT340 catalog."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIR = ROOT / "vt340-research" / "roms"
CATALOG_PATH = CATALOG_DIR / "catalog.json"


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def load_catalog() -> tuple[dict, dict[str, dict]]:
    catalog = load_json(CATALOG_PATH)
    if catalog.get("schema_version") != 1:
        raise SystemExit("unsupported ROM catalog schema")
    sets: dict[str, dict] = {}
    for entry in catalog["sets"]:
        manifest = load_json(CATALOG_DIR / entry["manifest"])
        if manifest["id"] != entry["id"]:
            raise SystemExit(f"set ID mismatch in {entry['manifest']}")
        sets[entry["id"]] = {**entry, "data": manifest}
    return catalog, sets


def digest(data: bytes) -> dict[str, str | int]:
    return {
        "size": len(data),
        "crc32": f"{binascii.crc32(data) & 0xffffffff:08x}",
        "sha1": hashlib.sha1(data).hexdigest(),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def verify_bytes(image: dict, data: bytes, label: str) -> list[str]:
    observed = digest(data)
    errors = []
    for field in ("size", "crc32", "sha1", "sha256"):
        expected = image[field]
        if observed[field] != expected:
            errors.append(f"{label}: {field} expected {expected}, observed {observed[field]}")
    return errors


def atomic_copy(data: bytes, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
    try:
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def selected_sets(sets: dict[str, dict], set_id: str | None) -> list[dict]:
    if set_id:
        if set_id not in sets:
            raise SystemExit(f"unknown ROM set: {set_id}")
        return [sets[set_id]]
    return list(sets.values())


def library_dir(binary_root: Path, rom_set: dict) -> Path:
    return binary_root / rom_set["library_path"]


def cmd_list(catalog: dict, sets: dict[str, dict]) -> int:
    print("ROM sets:")
    for entry in catalog["sets"]:
        data = sets[entry["id"]]["data"]
        version = data["release"].get("firmware_version") or "unversioned"
        print(f"  {entry['id']:<28} {version:<12} {data['status']:<10} {entry['title']}")
    print("\nProfiles:")
    for profile in catalog["profiles"]:
        print(f"  {profile['id']:<28} {', '.join(profile['sets'])}")
    return 0


def import_set(binary_root: Path, rom_set: dict) -> list[str]:
    errors: list[str] = []
    destination_dir = library_dir(binary_root, rom_set)
    system = rom_set["data"]["system"]
    archive = None
    if system == "lk201":
        archive_path = binary_root / rom_set["data"]["compatibility"]["archive_path"]
        if not archive_path.exists():
            return [f"{rom_set['id']}: active archive is missing: {archive_path}"]
        archive = zipfile.ZipFile(archive_path)
    try:
        for image in rom_set["data"]["images"]:
            if archive:
                try:
                    data = archive.read(image["filename"])
                except KeyError:
                    errors.append(f"{rom_set['id']}: archive member missing: {image['filename']}")
                    continue
                source_label = f"{archive.filename}:{image['filename']}"
            else:
                source = binary_root / image["active_path"]
                if not source.exists():
                    errors.append(f"{rom_set['id']}: active image is missing: {source}")
                    continue
                data = source.read_bytes()
                source_label = str(source)
            errors.extend(verify_bytes(image, data, source_label))
            destination = destination_dir / image["filename"]
            if destination.exists():
                existing_errors = verify_bytes(image, destination.read_bytes(), str(destination))
                if existing_errors:
                    errors.append(f"{destination}: refusing to replace a different library image")
                    errors.extend(existing_errors)
                continue
            if not errors or not any(source_label in error for error in errors):
                atomic_copy(data, destination)
                print(f"IMPORTED {rom_set['id']} {image['filename']} -> {destination}")
    finally:
        if archive:
            archive.close()
    return errors


def cmd_import(catalog: dict, sets: dict[str, dict], set_id: str | None) -> int:
    binary_root = ROOT / catalog["binary_root"]
    errors = []
    for rom_set in selected_sets(sets, set_id):
        errors.extend(import_set(binary_root, rom_set))
    if errors:
        print("\n".join(f"ERROR {error}" for error in errors), file=sys.stderr)
        return 1
    return cmd_verify(catalog, sets, set_id, "library")


def read_image(binary_root: Path, rom_set: dict, image: dict, location: str) -> tuple[bytes | None, str]:
    if location == "library":
        path = library_dir(binary_root, rom_set) / image["filename"]
        return (path.read_bytes() if path.exists() else None, str(path))
    if rom_set["data"]["system"] == "lk201":
        archive_path = binary_root / rom_set["data"]["compatibility"]["archive_path"]
        label = f"{archive_path}:{image['filename']}"
        if not archive_path.exists():
            return None, label
        with zipfile.ZipFile(archive_path) as archive:
            try:
                return archive.read(image["filename"]), label
            except KeyError:
                return None, label
    path = binary_root / image["active_path"]
    return (path.read_bytes() if path.exists() else None, str(path))


def cmd_verify(catalog: dict, sets: dict[str, dict], set_id: str | None, location: str,
               profile_id: str | None = None) -> int:
    binary_root = ROOT / catalog["binary_root"]
    errors = []
    verified = 0
    if profile_id:
        profiles = {profile["id"]: profile for profile in catalog["profiles"]}
        if profile_id not in profiles:
            raise SystemExit(f"unknown ROM profile: {profile_id}")
        verify_sets = [sets[item] for item in profiles[profile_id]["sets"]]
    else:
        verify_sets = selected_sets(sets, set_id)
    for rom_set in verify_sets:
        for image in rom_set["data"]["images"]:
            data, label = read_image(binary_root, rom_set, image, location)
            if data is None:
                errors.append(f"{label}: missing")
                continue
            image_errors = verify_bytes(image, data, label)
            errors.extend(image_errors)
            if not image_errors:
                verified += 1
                print(f"OK {rom_set['id']} {image['filename']} ({location})")
    if errors:
        print("\n".join(f"ERROR {error}" for error in errors), file=sys.stderr)
        return 1
    print(f"Verified {verified} ROM images in {location} storage")
    return 0


def cmd_activate(catalog: dict, sets: dict[str, dict], profile_id: str) -> int:
    profiles = {profile["id"]: profile for profile in catalog["profiles"]}
    if profile_id not in profiles:
        raise SystemExit(f"unknown ROM profile: {profile_id}")
    profile = profiles[profile_id]
    binary_root = ROOT / catalog["binary_root"]
    for set_id in profile["sets"]:
        if cmd_verify(catalog, sets, set_id, "library"):
            return 1
    with tempfile.TemporaryDirectory(prefix="vt340-rom-activate-", dir=binary_root) as temporary:
        stage = Path(temporary)
        targets: list[tuple[Path, Path]] = []
        for set_id in profile["sets"]:
            rom_set = sets[set_id]
            images = rom_set["data"]["images"]
            if rom_set["data"]["system"] == "lk201":
                archive_name = rom_set["data"]["compatibility"]["archive_path"]
                staged_archive = stage / archive_name
                staged_archive.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(staged_archive, "w", zipfile.ZIP_DEFLATED) as archive:
                    for image in images:
                        data = (library_dir(binary_root, rom_set) / image["filename"]).read_bytes()
                        info = zipfile.ZipInfo(image["filename"], (1980, 1, 1, 0, 0, 0))
                        info.compress_type = zipfile.ZIP_DEFLATED
                        info.external_attr = 0o644 << 16
                        archive.writestr(info, data)
                targets.append((staged_archive, binary_root / archive_name))
            else:
                for image in images:
                    staged = stage / image["active_path"]
                    staged.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(library_dir(binary_root, rom_set) / image["filename"], staged)
                    targets.append((staged, binary_root / image["active_path"]))
        for staged, destination in targets:
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staged, destination)
            print(f"ACTIVATED {destination}")
    for set_id in profile["sets"]:
        if cmd_verify(catalog, sets, set_id, "active"):
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary-root", type=Path,
                        help="override the local ignored ROM root (mainly for isolated validation)")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list", help="list known ROM sets and profiles")
    import_parser = subparsers.add_parser("import-current", help="copy active ROMs into versioned storage")
    import_parser.add_argument("--set", dest="set_id")
    verify_parser = subparsers.add_parser("verify", help="verify catalogued images")
    verify_group = verify_parser.add_mutually_exclusive_group()
    verify_group.add_argument("--set", dest="set_id")
    verify_group.add_argument("--profile", dest="profile_id")
    verify_parser.add_argument("--location", choices=("library", "active"), default="library")
    activate_parser = subparsers.add_parser("activate", help="activate a profile for MAME")
    activate_parser.add_argument("profile")
    args = parser.parse_args()
    catalog, sets = load_catalog()
    if args.binary_root:
        catalog["binary_root"] = str(args.binary_root.resolve())
    if args.command == "list":
        return cmd_list(catalog, sets)
    if args.command == "import-current":
        return cmd_import(catalog, sets, args.set_id)
    if args.command == "verify":
        return cmd_verify(catalog, sets, args.set_id, args.location, args.profile_id)
    return cmd_activate(catalog, sets, args.profile)


if __name__ == "__main__":
    raise SystemExit(main())
