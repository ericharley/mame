#!/usr/bin/env python3
"""Manifest-driven VT340 test runner and artifact recorder."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import mimetypes
import os
import platform
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path


TEST_DIR = Path(__file__).resolve().parent
ROOT = TEST_DIR.parent.parent
MANIFEST_PATH = TEST_DIR / "manifest.json"
DEFAULT_RESULTS = ROOT / "vt340-research" / "test-results"


def read_manifest() -> dict:
    with MANIFEST_PATH.open(encoding="utf-8") as stream:
        manifest = json.load(stream)
    if manifest.get("schema_version") != 1:
        raise SystemExit("unsupported test manifest schema")
    ids = [test["id"] for test in manifest["tests"]]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate test id in manifest")
    scripts = {path.name for path in TEST_DIR.glob("*.sh")}
    catalogued = {test["script"] for test in manifest["tests"]}
    missing = sorted(scripts - catalogued)
    stale = sorted(catalogued - scripts)
    if missing or stale:
        raise SystemExit(f"manifest/script mismatch: uncatalogued={missing}, missing={stale}")
    known = set(ids)
    for test in manifest["tests"]:
        references = ([test["alias_of"]] if test.get("kind") == "alias" else []) + test.get("members", [])
        unknown = sorted(set(references) - known)
        if unknown:
            raise SystemExit(f"{test['id']}: unknown referenced tests: {unknown}")
    return manifest


def git_value(*args: str) -> str | None:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_metadata(path: Path, base: Path) -> dict:
    stat = path.stat()
    media_type = "application/x-ndjson" if path.suffix == ".jsonl" else (
        mimetypes.guess_type(path.name)[0] or "application/octet-stream")
    return {
        "path": str(path.relative_to(base)),
        "bytes": stat.st_size,
        "sha256": sha256(path),
        "media_type": media_type,
    }


def select_tests(manifest: dict, selectors: list[str], include_nonatomic: bool) -> list[dict]:
    by_id = {test["id"]: test for test in manifest["tests"]}
    suites = manifest["suites"]
    if not selectors:
        selectors = ["quick"]
    selected: list[dict] = []
    seen: set[str] = set()
    for selector in selectors:
        if selector.startswith("@"):
            selector = selector[1:]
        if selector in suites:
            candidates = [
                test for test in manifest["tests"]
                if (selector == "all" or selector in test.get("suites", []))
                and (include_nonatomic or test.get("kind", "atomic") == "atomic")
            ]
        elif selector in by_id:
            candidates = [by_id[selector]]
        else:
            raise SystemExit(f"unknown test or suite: {selector}")
        resolved: list[dict] = []
        for candidate in candidates:
            if candidate.get("kind") == "alias":
                resolved.append(by_id[candidate["alias_of"]])
            elif candidate.get("kind") == "aggregate" and candidate.get("members"):
                resolved.extend(by_id[test_id] for test_id in candidate["members"])
            else:
                resolved.append(candidate)
        candidates = resolved
        for test in candidates:
            if test["id"] not in seen:
                selected.append(test)
                seen.add(test["id"])
    return selected


def command_for(test: dict, binary: Path) -> list[str]:
    command = [str(TEST_DIR / test["script"])]
    if test.get("accepts_binary", True):
        command.append(str(binary))
    return command


def validate_selection(tests: list[dict]) -> None:
    problems: list[str] = []
    for test in tests:
        for tool in test.get("requires", []):
            if shutil.which(tool) is None:
                problems.append(f"{test['id']}: required tool is unavailable: {tool}")
        for fixture in test.get("fixtures", []):
            path = ROOT / "vt340-research" / fixture
            if not path.exists():
                problems.append(f"{test['id']}: fixture is missing: {path}")
        for external in test.get("external_inputs", []):
            path = ROOT / external
            if not path.exists():
                problems.append(f"{test['id']}: external input is missing: {path}")
    if any(test.get("requires_roms") for test in tests):
        catalog_path = ROOT / "vt340-research" / "roms" / "catalog.json"
        with catalog_path.open(encoding="utf-8") as stream:
            catalog = json.load(stream)
        defaults = [profile["id"] for profile in catalog["profiles"] if profile.get("status") == "default"]
        if len(defaults) != 1:
            problems.append(f"ROM catalog must define exactly one default profile; found {defaults}")
        else:
            check = subprocess.run(
                [str(ROOT / "vt340-research" / "tools" / "rom_catalog.py"),
                 "verify", "--profile", defaults[0], "--location", "active"],
                cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                check=False)
            if check.returncode:
                problems.append("active ROM profile verification failed:\n" + check.stdout.rstrip())
    if problems:
        raise SystemExit("test preflight failed:\n  " + "\n  ".join(problems))


def run_test(test: dict, binary: Path, run_dir: Path, revision: str | None,
             dirty: bool, verbose: bool) -> dict:
    test_dir = run_dir / test["id"]
    artifact_dir = test_dir / "artifacts"
    artifact_dir.mkdir(parents=True)
    stdout_path = test_dir / "stdout.log"
    stderr_path = test_dir / "stderr.log"
    command = command_for(test, binary)
    env = os.environ.copy()
    env["VT340_TEST_ARTIFACT_DIR"] = str(artifact_dir)
    started = dt.datetime.now(dt.timezone.utc)
    begin = time.monotonic()
    if verbose:
        print(f"RUN  {test['id']}: {test['title']}", flush=True)
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        process = subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr,
                                 check=False)
    ended = dt.datetime.now(dt.timezone.utc)
    missing_outputs = [
        pattern for pattern in test.get("outputs", [])
        if not any(artifact_dir.glob(pattern))
    ]
    effective_exit_code = process.returncode
    if process.returncode == 0 and missing_outputs:
        effective_exit_code = 98
    files = sorted(path for path in test_dir.rglob("*") if path.is_file())
    result = {
        "schema_version": 1,
        "test": test,
        "command": command,
        "working_directory": str(ROOT),
        "binary": str(binary),
        "git_revision": revision,
        "git_dirty": dirty,
        "started_utc": started.isoformat(),
        "ended_utc": ended.isoformat(),
        "duration_seconds": round(time.monotonic() - begin, 6),
        "command_exit_code": process.returncode,
        "exit_code": effective_exit_code,
        "status": "passed" if effective_exit_code == 0 else "failed",
        "missing_declared_outputs": missing_outputs,
        "artifacts": [file_metadata(path, test_dir) for path in files],
    }
    metadata_path = test_dir / "metadata.json"
    metadata_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if verbose:
        print(f"{'PASS' if effective_exit_code == 0 else 'FAIL'} {test['id']} "
              f"({result['duration_seconds']:.2f}s)", flush=True)
        if missing_outputs:
            print(f"     missing declared outputs: {', '.join(missing_outputs)}", flush=True)
    return result


def list_tests(manifest: dict) -> int:
    print("ID                         KIND       SECONDS  SUITES")
    for test in manifest["tests"]:
        print(f"{test['id']:<26} {test.get('kind', 'atomic'):<10} "
              f"{test.get('estimated_seconds', 0):>7}  {','.join(test.get('suites', []))}")
    print("\nSuites:")
    for suite, description in manifest["suites"].items():
        print(f"  {suite:<12} {description}")
    return 0


def write_report(run_dir: Path, summary: dict, results: list[dict]) -> None:
    lines = [
        f"# VT340 test run `{summary['run_id']}`",
        "",
        f"- Revision: `{summary['git_revision']}`",
        f"- Dirty worktree: `{'yes' if summary['git_dirty'] else 'no'}`",
        f"- Result: **{summary['passed']} passed, {summary['failed']} failed**",
        f"- Recorded duration: `{summary['duration_seconds']:.3f}` seconds",
        "",
        "| Test | Status | Duration | Evidence |",
        "| --- | --- | ---: | --- |",
    ]
    for result in results:
        test_id = result["test"]["id"]
        evidence = f"[metadata]({test_id}/metadata.json), [stdout]({test_id}/stdout.log), [stderr]({test_id}/stderr.log)"
        lines.append(
            f"| `{test_id}` | {result['status']} | {result['duration_seconds']:.3f}s | {evidence} |")
    images = [
        (result["test"]["id"], artifact["path"])
        for result in results for artifact in result["artifacts"]
        if artifact["media_type"].startswith("image/")
    ]
    if images:
        lines.extend(["", "## Graphical outputs", ""])
        for test_id, path in images:
            lines.extend([
                f"### `{test_id}` — `{Path(path).name}`",
                "",
                f"![{test_id} {Path(path).name}]({test_id}/{path})",
                "",
            ])
    (run_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("list", help="list catalogued tests and suites")
    run_parser = subparsers.add_parser("run", help="run tests or @suite selectors")
    run_parser.add_argument("selectors", nargs="*", help="test IDs or suite names (default: quick)")
    run_parser.add_argument("--binary", default="./vt340", help="VT340 executable")
    run_parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS,
                            help="parent directory for timestamped runs")
    run_parser.add_argument("--include-nonatomic", action="store_true",
                            help="include aliases and aggregate wrappers in suite selection")
    run_parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    manifest = read_manifest()
    if args.action == "list":
        return list_tests(manifest)

    tests = select_tests(manifest, args.selectors, args.include_nonatomic)
    validate_selection(tests)
    binary = (ROOT / args.binary).resolve() if not Path(args.binary).is_absolute() else Path(args.binary)
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    revision = git_value("rev-parse", "HEAD")
    short_revision = revision[:8] if revision else "nogit"
    results_root = args.results.resolve()
    results_root.mkdir(parents=True, exist_ok=True)
    base_run_id = f"{now}-{short_revision}"
    run_dir = results_root / base_run_id
    suffix = 2
    while run_dir.exists():
        run_dir = results_root / f"{base_run_id}-{suffix:02d}"
        suffix += 1
    run_dir.mkdir()
    dirty = bool(git_value("status", "--porcelain"))
    run_info = {
        "schema_version": 1,
        "run_id": run_dir.name,
        "host": socket.gethostname(),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "git_revision": revision,
        "git_dirty": dirty,
        "manifest": str(MANIFEST_PATH.relative_to(ROOT)),
        "selectors": args.selectors or ["quick"],
        "tests": [test["id"] for test in tests],
    }
    (run_dir / "run.json").write_text(json.dumps(run_info, indent=2) + "\n", encoding="utf-8")
    results = [run_test(test, binary, run_dir, revision, dirty, not args.quiet) for test in tests]
    summary = {
        **run_info,
        "passed": sum(result["status"] == "passed" for result in results),
        "failed": sum(result["status"] == "failed" for result in results),
        "duration_seconds": round(sum(result["duration_seconds"] for result in results), 6),
        "results": [{key: result[key] for key in ("status", "exit_code", "duration_seconds")}
                    | {"id": result["test"]["id"]} for result in results],
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    write_report(run_dir, summary, results)
    print(f"Results: {run_dir}")
    print(f"Summary: {summary['passed']} passed, {summary['failed']} failed")
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
