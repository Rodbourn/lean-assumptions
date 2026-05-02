from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schema" / "report-v1.schema.json"
BATCH_SCHEMA_PATH = ROOT / "schema" / "batch-report-v1.schema.json"
DELTA_SCHEMA_PATH = ROOT / "schema" / "delta-report-v1.schema.json"
CLUSTER_SCHEMA_PATH = ROOT / "schema" / "cluster-report-v1.schema.json"
GOLDEN_DIR = ROOT / "LeanAssumptionsTest" / "Golden"


def json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, (int, float)):
        return "number"
    return type(value).__name__


def resolve_ref(schema: dict[str, Any], ref: str) -> dict[str, Any]:
    prefix = "#/$defs/"
    if not ref.startswith(prefix):
        raise ValueError(f"unsupported schema reference: {ref}")
    name = ref[len(prefix) :]
    return schema["$defs"][name]


def check_type(expected: Any, value: Any, path: str, errors: list[str]) -> None:
    actual = json_type(value)
    if isinstance(expected, list):
        if actual not in expected:
            errors.append(f"{path}: expected one of {expected}, got {actual}")
    elif actual != expected:
        errors.append(f"{path}: expected {expected}, got {actual}")


def validate(schema: dict[str, Any], spec: dict[str, Any], value: Any, path: str, errors: list[str]) -> None:
    if "$ref" in spec:
        validate(schema, resolve_ref(schema, spec["$ref"]), value, path, errors)
        return

    if "const" in spec and value != spec["const"]:
        errors.append(f"{path}: expected constant {spec['const']!r}, got {value!r}")

    if "enum" in spec and value not in spec["enum"]:
        errors.append(f"{path}: expected enum value from {spec['enum']!r}, got {value!r}")

    if "type" in spec:
        check_type(spec["type"], value, path, errors)

    if isinstance(value, dict):
        required = spec.get("required", [])
        for key in required:
            if key not in value:
                errors.append(f"{path}: missing required key {key!r}")

        properties = spec.get("properties", {})
        if spec.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"{path}: unexpected key {key!r}")

        for key, child_spec in properties.items():
            if key in value:
                validate(schema, child_spec, value[key], f"{path}.{key}", errors)

    if isinstance(value, list) and "items" in spec:
        for index, item in enumerate(value):
            validate(schema, spec["items"], item, f"{path}[{index}]", errors)


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    batch_schema = json.loads(BATCH_SCHEMA_PATH.read_text(encoding="utf-8"))
    delta_schema = json.loads(DELTA_SCHEMA_PATH.read_text(encoding="utf-8"))
    cluster_schema = json.loads(CLUSTER_SCHEMA_PATH.read_text(encoding="utf-8"))
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
        rel_path = path.relative_to(ROOT).as_posix()
        if isinstance(value, dict) and "clusters" in value:
            validate(cluster_schema, cluster_schema, value, rel_path, errors)
        elif isinstance(value, dict) and "changes" in value:
            validate(delta_schema, delta_schema, value, rel_path, errors)
        elif isinstance(value, dict) and "reports" in value:
            validate(batch_schema, batch_schema, value, rel_path, errors)
            for index, report in enumerate(value.get("reports", [])):
                validate(schema, schema, report, f"{rel_path}.reports[{index}]", errors)
        else:
            validate(schema, schema, value, rel_path, errors)

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Report schema validated for {len(json_files)} golden JSON file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
