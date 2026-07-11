from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover - fail closed with guidance
    print(
        "check_policy_schema.py requires the 'jsonschema' package "
        "(python3 -m pip install jsonschema). Refusing to validate without it.",
        file=sys.stderr,
    )
    raise SystemExit(1)


ROOT = Path(__file__).resolve().parent.parent
POLICY_SCHEMA_PATH = ROOT / "schema" / "policy-v1.schema.json"
FIXTURES_DIR = ROOT / "LeanAssumptionsTest" / "Fixtures"


def main() -> int:
    schema = json.loads(POLICY_SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    # Every policy fixture is validated against the published schema itself,
    # so the schema file and the accepted fixture corpus cannot drift apart.
    fixtures = sorted(FIXTURES_DIR.glob("policy-*.json"))
    errors: list[str] = []

    if not fixtures:
        errors.append(f"No policy fixtures found under {FIXTURES_DIR.relative_to(ROOT)}.")

    for path in fixtures:
        rel = path.relative_to(ROOT).as_posix()
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{rel}: invalid JSON: {exc}")
            continue
        for error in sorted(validator.iter_errors(value), key=lambda e: list(e.absolute_path)):
            location = "/".join(str(part) for part in error.absolute_path) or "<root>"
            errors.append(f"{rel} @ {location}: {error.message}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(
        f"Policy schema validated for {len(fixtures)} policy file(s) "
        "against schema/policy-v1.schema.json (jsonschema Draft 2020-12)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
