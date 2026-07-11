from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover - fail closed with guidance
    print(
        "check_report_schema.py requires the 'jsonschema' package "
        "(python3 -m pip install jsonschema). Refusing to validate without it.",
        file=sys.stderr,
    )
    raise SystemExit(1)


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schema" / "report-v1.schema.json"
BATCH_SCHEMA_PATH = ROOT / "schema" / "batch-report-v1.schema.json"
DELTA_SCHEMA_PATH = ROOT / "schema" / "delta-report-v1.schema.json"
CLUSTER_SCHEMA_PATH = ROOT / "schema" / "cluster-report-v1.schema.json"
GOLDEN_DIR = ROOT / "LeanAssumptionsTest" / "Golden"

# A freshly emitted artifact is validated on every run so the schema gate can
# never pass on checked-in goldens alone while live output drifts.
FRESH_ARTIFACT_COMMAND = [
    "lake", "env", "lean-assumptions",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage",
]


def load_validator(path: Path) -> Draft202012Validator:
    schema = json.loads(path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validate_value(validator: Draft202012Validator, value: Any, label: str,
                   errors: list[str]) -> None:
    for error in sorted(validator.iter_errors(value), key=lambda e: list(e.absolute_path)):
        location = "/".join(str(part) for part in error.absolute_path) or "<root>"
        errors.append(f"{label} @ {location}: {error.message}")


def classify_and_validate(validators: dict[str, Draft202012Validator], value: Any,
                          label: str, errors: list[str]) -> None:
    if isinstance(value, dict) and "clusters" in value:
        validate_value(validators["cluster"], value, label, errors)
    elif isinstance(value, dict) and "changes" in value:
        validate_value(validators["delta"], value, label, errors)
    elif isinstance(value, dict) and "reports" in value:
        validate_value(validators["batch"], value, label, errors)
        for index, report in enumerate(value.get("reports", [])):
            validate_value(validators["report"], report, f"{label}.reports[{index}]", errors)
    else:
        validate_value(validators["report"], value, label, errors)


def validate_fresh_artifact(validators: dict[str, Draft202012Validator],
                            errors: list[str]) -> bool:
    if os.environ.get("CHECK_REPORT_SCHEMA_SKIP_FRESH") == "1":
        # Explicit opt-out for contexts without a built CLI (e.g. the update
        # workflow). Never silent: the skip is announced in the summary line.
        print(
            "fresh artifact validation SKIPPED (CHECK_REPORT_SCHEMA_SKIP_FRESH=1); "
            "golden files only.",
        )
        return False
    completed = subprocess.run(
        FRESH_ARTIFACT_COMMAND, cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        errors.append(
            "fresh artifact: CLI invocation failed "
            f"(exit {completed.returncode}); build the executable first "
            f"(lake build lean-assumptions LeanAssumptionsTest.Fixtures): {completed.stderr.strip()[:400]}"
        )
        return False
    try:
        value = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        errors.append(f"fresh artifact: CLI emitted invalid JSON: {exc}")
        return False
    classify_and_validate(validators, value, "fresh CLI artifact", errors)
    return True


def main() -> int:
    validators = {
        "report": load_validator(SCHEMA_PATH),
        "batch": load_validator(BATCH_SCHEMA_PATH),
        "delta": load_validator(DELTA_SCHEMA_PATH),
        "cluster": load_validator(CLUSTER_SCHEMA_PATH),
    }
    json_files = sorted(GOLDEN_DIR.rglob("*.json"))
    errors: list[str] = []

    if not json_files:
        errors.append("No golden JSON files found.")

    for path in json_files:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{path.relative_to(ROOT)}: invalid JSON: {exc}")
            continue
        classify_and_validate(validators, value, path.relative_to(ROOT).as_posix(), errors)

    fresh_ok = validate_fresh_artifact(validators, errors)

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(
        f"Report schema validated for {len(json_files)} golden JSON file(s) "
        f"plus {'a fresh CLI artifact' if fresh_ok else 'no fresh artifact'} "
        "(jsonschema Draft 2020-12)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
