#!/usr/bin/env python3
"""Validate and render the DC323 command-to-test coverage matrix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


TEST_DIR = Path(__file__).resolve().parent.parent
CATALOG_PATH = TEST_DIR / "dc323-command-catalog.json"
MANIFEST_PATH = TEST_DIR / "manifest.json"
CASES_PATH = TEST_DIR / "vt340test-cases.json"
REPORT_PATH = TEST_DIR / "dc323-command-coverage.md"
LEVELS = {"direct", "integration", "negative", "observed"}
STATUSES = {"implemented", "partial", "no-op", "unsupported"}
SATISFIES = {
    "none": LEVELS,
    "integration": {"direct", "integration"},
    "direct": {"direct"},
}


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def escape(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def collect_claims(manifest: dict, cases: dict, known: set[str]) -> tuple[list[dict], list[str]]:
    claims: list[dict] = []
    errors: list[str] = []

    def add(owner: str, entries: list[dict]) -> None:
        seen: set[tuple[str, str]] = set()
        for entry in entries:
            family = entry.get("family", "")
            level = entry.get("level", "")
            key = (family, level)
            if family not in known:
                errors.append(f"{owner}: unknown DC323 command family {family!r}")
            if level not in LEVELS:
                errors.append(f"{owner}: invalid DC323 coverage level {level!r}")
            if not entry.get("scope"):
                errors.append(f"{owner}: DC323 claim {family!r} has no scope")
            if key in seen:
                errors.append(f"{owner}: duplicate DC323 claim {family!r}/{level!r}")
            seen.add(key)
            claims.append({"owner": owner, **entry})

    for test in manifest["tests"]:
        add(test["id"], test.get("dc323_commands", []))
    for case in cases["cases"]:
        add(f"vt340test-corpus/{case['id']}", case.get("dc323_commands", []))
    return claims, errors


def render(catalog: dict, claims: list[dict]) -> tuple[str, list[str]]:
    by_family: dict[str, list[dict]] = {family["id"]: [] for family in catalog["families"]}
    for claim in claims:
        if claim["family"] in by_family:
            by_family[claim["family"]].append(claim)

    errors: list[str] = []
    lines = [
        "# DC323 command implementation and test coverage",
        "",
        "This file is generated from `dc323-command-catalog.json`, test claims in",
        "`manifest.json`, and per-case claims in `vt340test-cases.json`. Run",
        "`tests/dc323-command-coverage.sh` after changing DC323 behavior or tests.",
        "",
        "Coverage levels: **direct** is a targeted firmware-free assertion;",
        "**integration** couples native command activity to an asserted visible or",
        "read-back result; **negative** verifies a no-draw/unsupported boundary; and",
        "**observed** records trace occurrence without claiming semantic coverage.",
        "",
        "| Command family | Encoding/context | State | Required | Coverage | Remaining boundary |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for family in catalog["families"]:
        family_claims = sorted(by_family[family["id"]], key=lambda item: (item["level"], item["owner"]))
        coverage = "; ".join(
            f"`{claim['owner']}` ({claim['level']})" for claim in family_claims) or "—"
        required = family["required_level"]
        if required != "none" and not any(
                claim["level"] in SATISFIES[required] for claim in family_claims):
            errors.append(f"{family['id']}: requires {required} coverage")
            coverage = "**MISSING**" + (f"; {coverage}" if family_claims else "")
        lines.append(
            f"| `{family['id']}` — {escape(family['title'])} | {escape(family['encoding'])} | "
            f"{family['status']} | {required} | {coverage} | {escape(family['remaining'])} |")

    lines += [
        "",
        "## Per-test scope",
        "",
        "| Test or case | Level | Command family | What the test actually asserts |",
        "| --- | --- | --- | --- |",
    ]
    for claim in sorted(claims, key=lambda item: (item["owner"], item["family"], item["level"])):
        lines.append(
            f"| `{claim['owner']}` | {claim['level']} | `{claim['family']}` | "
            f"{escape(claim['scope'])} |")
    lines += [
        "",
        "## Change policy",
        "",
        "When a family moves from `unsupported` to `partial` or `implemented`, give",
        "it the required direct/integration claim in the same change. A test should",
        "claim only behavior it asserts; merely seeing a command in a boot trace is",
        "`observed`, not functional coverage. Split a family when new behavior has a",
        "distinct mode or state boundary that can regress independently.",
        "",
    ]
    return "\n".join(lines), errors


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--check", action="store_true", help="fail if coverage or report is stale")
    action.add_argument("--write", action="store_true", help="write the generated report")
    args = parser.parse_args()

    catalog = load(CATALOG_PATH)
    manifest = load(MANIFEST_PATH)
    cases = load(CASES_PATH)
    if catalog.get("schema_version") != 1:
        raise SystemExit("unsupported DC323 command catalog schema")
    ids = [family["id"] for family in catalog["families"]]
    errors = ["duplicate DC323 command family"] if len(ids) != len(set(ids)) else []
    for family in catalog["families"]:
        if family["status"] not in STATUSES:
            errors.append(f"{family['id']}: invalid implementation status")
        if family["required_level"] not in SATISFIES:
            errors.append(f"{family['id']}: invalid required level")
        elif family["status"] == "unsupported" and family["required_level"] != "none":
            errors.append(f"{family['id']}: unsupported family must not require positive coverage")
        elif family["status"] != "unsupported" and family["required_level"] == "none":
            errors.append(f"{family['id']}: implemented/partial/no-op family requires coverage")
    claims, claim_errors = collect_claims(manifest, cases, set(ids))
    report, coverage_errors = render(catalog, claims)
    errors += claim_errors + coverage_errors

    if args.write:
        REPORT_PATH.write_text(report, encoding="utf-8")
    elif not REPORT_PATH.exists() or REPORT_PATH.read_text(encoding="utf-8") != report:
        errors.append("dc323-command-coverage.md is stale; run dc323_coverage.py --write")

    if errors:
        for error in errors:
            print(f"DC323 coverage error: {error}")
        return 1
    print(f"DC323 command coverage passed: {len(ids)} families, {len(claims)} test claims")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
