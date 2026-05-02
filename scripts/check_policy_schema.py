from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
POLICY_SCHEMA_PATH = ROOT / "schema" / "policy-v1.schema.json"
POLICY_FIXTURES = [
    ROOT / "LeanAssumptionsTest" / "Fixtures" / "policy-allow-package.json",
    ROOT / "LeanAssumptionsTest" / "Fixtures" / "policy-reducible-allow-package.json",
]


def fail(path: str, message: str, errors: list[str]) -> None:
    errors.append(f"{path}: {message}")


def require_type(path: str, value: Any, expected_type: type, errors: list[str]) -> bool:
    if not isinstance(value, expected_type):
        fail(path, f"expected {expected_type.__name__}, got {type(value).__name__}", errors)
        return False
    return True


def validate_name_pattern(path: str, value: Any, errors: list[str]) -> None:
    if isinstance(value, str):
        return
    if isinstance(value, dict):
        keys = set(value)
        if keys == {"exact"} and isinstance(value["exact"], str):
            return
        if keys == {"prefix"} and isinstance(value["prefix"], str):
            return
    fail(path, "expected string, {\"exact\": string}, or {\"prefix\": string}", errors)


def validate_policy(path: Path, value: Any, errors: list[str]) -> None:
    rel = path.relative_to(ROOT).as_posix()
    if not require_type(rel, value, dict, errors):
        return

    allowed = {
        "version",
        "identifier",
        "transparency_mode",
        "permit_direct_props",
        "permit_package_types",
        "typeclass_policy",
        "unknown_policy",
    }
    for key in value:
        if key not in allowed:
            fail(rel, f"unexpected key {key!r}", errors)

    if value.get("version") != 1:
        fail(rel, "version must be 1", errors)

    if "identifier" in value:
        require_type(f"{rel}.identifier", value["identifier"], str, errors)

    if value.get("transparency_mode", "none") not in {"none", "reducible", "recursive_normalization"}:
        fail(f"{rel}.transparency_mode", "unsupported transparency mode", errors)

    for key in ("permit_direct_props", "permit_package_types"):
        entries = value.get(key, [])
        if require_type(f"{rel}.{key}", entries, list, errors):
            for index, entry in enumerate(entries):
                validate_name_pattern(f"{rel}.{key}[{index}]", entry, errors)

    for key in ("typeclass_policy", "unknown_policy"):
        if value.get(key, "fail") not in {"allow", "warn", "fail"}:
            fail(f"{rel}.{key}", "unsupported treatment", errors)


def main() -> int:
    json.loads(POLICY_SCHEMA_PATH.read_text(encoding="utf-8"))
    errors: list[str] = []

    for path in POLICY_FIXTURES:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{path.relative_to(ROOT)}: invalid JSON: {exc}")
            continue
        validate_policy(path, value, errors)

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Policy schema validated for {len(POLICY_FIXTURES)} policy file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
