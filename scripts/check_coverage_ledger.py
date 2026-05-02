from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LEDGER_PATH = ROOT / "schema" / "coverage-ledger.json"


def collect_lean_files() -> list[str]:
    paths: list[str] = []
    for path in ROOT.rglob("*.lean"):
        rel = path.relative_to(ROOT)
        if rel.parts and rel.parts[0] == ".lake":
            continue
        paths.append(rel.as_posix())
    return sorted(paths)


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
        for definition in entry.get("publicDefinitions", []):
            def_tests = definition.get("tests", [])
            if not def_tests:
                errors.append(f"Public definition {definition.get('name', '<unknown>')} in {path} has no mapped tests.")

    if errors:
        print("\n\n".join(errors), file=sys.stderr)
        return 1

    print(f"Coverage ledger validated for {len(expected)} Lean files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
