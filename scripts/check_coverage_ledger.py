from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LEDGER_PATH = ROOT / "schema" / "coverage-ledger.json"
INVENTORY_PATH = ROOT / ".lake" / "build" / "lean-assumptions-test" / "public-surface.txt"

# Ledger test references that are commands rather than file paths must start
# with one of these; anything else path-shaped must exist on disk.
COMMAND_PREFIXES = ("lake ", "lake", "python3 ", "python ")


def collect_lean_files() -> list[str]:
    paths: list[str] = []
    # Build artifacts and untracked local tooling directories are out of
    # ledger scope; only published source participates in coverage.
    for path in ROOT.rglob("*.lean"):
        rel = path.relative_to(ROOT)
        if rel.parts and rel.parts[0] in (".lake", ".claude", ".vscode", ".idea"):
            continue
        paths.append(rel.as_posix())
    return sorted(paths)


def read_inventory() -> dict[str, set[str]]:
    """Read the public-surface inventory emitted while building the test suite.

    The inventory covers modules imported by the `LeanAssumptions` root (see
    LeanAssumptionsTest/Coverage.lean). Files outside it, such as the CLI
    executable root, keep shape-only validation.
    """
    inventory: dict[str, set[str]] = {}
    for line in INVENTORY_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        file_part, _, decl = line.partition("|")
        if not decl:
            continue
        inventory.setdefault(file_part, set()).add(decl)
    return inventory


def check_test_reference(reference: str, errors: list[str], context: str) -> None:
    looks_like_path = "/" in reference or reference.endswith((".lean", ".py", ".json", ".sh"))
    if looks_like_path and not reference.startswith(COMMAND_PREFIXES):
        if not (ROOT / reference).exists():
            errors.append(f"{context}: referenced test path does not exist: {reference}")
        return
    if not reference.startswith(COMMAND_PREFIXES):
        errors.append(
            f"{context}: unrecognized test reference (not a repo path or lake/python command): {reference}"
        )


def main() -> int:
    ledger = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
    entries = ledger.get("leanFiles", [])
    indexed = {entry["path"]: entry for entry in entries}
    expected = collect_lean_files()
    missing = [path for path in expected if path not in indexed]
    extra = [path for path in indexed if not (ROOT / path).exists()]
    errors: list[str] = []

    if missing:
        errors.append("Missing ledger entries:\n" + "\n".join(f"  - {path}" for path in missing))
    if extra:
        errors.append("Ledger entries reference missing files:\n" + "\n".join(f"  - {path}" for path in extra))

    for entry in entries:
        path = entry["path"]
        tests = entry.get("tests", [])
        if not tests:
            errors.append(f"Ledger entry {path} has no covering tests or validation commands.")
        for reference in tests:
            check_test_reference(reference, errors, f"Ledger entry {path}")
        for definition in entry.get("publicDefinitions", []):
            def_tests = definition.get("tests", [])
            if not def_tests:
                errors.append(
                    f"Public definition {definition.get('name', '<unknown>')} in {path} has no mapped tests."
                )
            for reference in def_tests:
                check_test_reference(
                    reference, errors,
                    f"Definition {definition.get('name', '<unknown>')} in {path}"
                )

    if not INVENTORY_PATH.exists():
        errors.append(
            f"Public-surface inventory missing: {INVENTORY_PATH.relative_to(ROOT)}\n"
            "  Run `lake test` (or `lake build LeanAssumptionsTest.Coverage`) first; "
            "the ledger cannot be validated for completeness without it."
        )
    else:
        inventory = read_inventory()
        # Completeness: every inventoried public declaration needs a ledger row.
        for file_path in sorted(inventory):
            entry = indexed.get(file_path)
            listed = {
                definition.get("name")
                for definition in (entry.get("publicDefinitions", []) if entry else [])
            }
            unlisted = sorted(inventory[file_path] - listed)
            if unlisted:
                errors.append(
                    f"Public declarations in {file_path} missing from the ledger:\n"
                    + "\n".join(f"  - {name}" for name in unlisted)
                )
        # Staleness: ledger rows for inventoried files must name real declarations.
        for file_path, entry in sorted(indexed.items()):
            if file_path not in inventory:
                continue
            for definition in entry.get("publicDefinitions", []):
                name = definition.get("name")
                if name not in inventory[file_path]:
                    errors.append(
                        f"Ledger entry {file_path} lists {name}, which is not a current public declaration."
                    )

    if errors:
        print("\n\n".join(errors), file=sys.stderr)
        return 1

    print(
        f"Coverage ledger validated for {len(expected)} Lean files "
        f"({sum(len(v) for v in read_inventory().values()) if INVENTORY_PATH.exists() else 0} public declarations)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
