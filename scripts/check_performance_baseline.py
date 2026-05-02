from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "LeanAssumptionsTest" / "Performance" / "baseline.json"


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a nonempty string")
    return value


def require_string_list(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field} must be a nonempty array")
    result: list[str] = []
    for index, item in enumerate(value):
        result.append(require_string(item, f"{field}[{index}]"))
    return result


def require_positive_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, int | float) or value <= 0:
        raise ValueError(f"{field} must be a positive number")
    return float(value)


def command_for(case: dict[str, Any]) -> list[str]:
    command = ["lake", "env", "lean-assumptions"]
    for module in require_string_list(case.get("modules"), "modules"):
        command.extend(["--module", module])
    for declaration in require_string_list(case.get("declarations"), "declarations"):
        command.extend(["--decl", declaration])
    output_format = require_string(case.get("format", "json"), "format")
    if output_format != "json":
        raise ValueError("performance baseline cases must use JSON output")
    command.extend(["--format", output_format])
    for option in require_string_list(case.get("extra_args", ["--allow-unknowns"]), "extra_args"):
        command.append(option)
    return command


def windows_path_to_wsl(path: Path) -> str:
    """Translate a Windows path to WSL's /mnt/<drive>/... form."""
    resolved = str(path.resolve()).replace("\\", "/")
    if len(resolved) >= 3 and resolved[1:3] == ":/":
        return f"/mnt/{resolved[0].lower()}{resolved[2:]}"
    raise ValueError(f"cannot translate non-drive Windows path to WSL: {path}")


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    """Run a Lake command natively, or via WSL when native Lake is unavailable."""
    if shutil.which(command[0]) is not None:
        return subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    if os.name == "nt" and shutil.which("wsl.exe") is not None:
        root = windows_path_to_wsl(ROOT)
        shell_command = " ".join(shlex.quote(part) for part in command)
        return subprocess.run(
            ["wsl.exe", "bash", "-lc", f"cd {shlex.quote(root)} && {shell_command}"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    raise FileNotFoundError(f"{command[0]} was not found on PATH")


def validate_case(case: Any, index: int) -> tuple[str, list[str], float]:
    if not isinstance(case, dict):
        raise ValueError(f"cases[{index}] must be an object")
    name = require_string(case.get("name"), f"cases[{index}].name")
    command = command_for(case)
    max_ms = require_positive_number(case.get("max_ms"), f"cases[{index}].max_ms")
    return name, command, max_ms


def main() -> int:
    if not BASELINE.exists():
        return fail(f"Missing performance baseline: {BASELINE.relative_to(ROOT).as_posix()}")

    data = json.loads(BASELINE.read_text(encoding="utf-8"))
    if data.get("version") != 1:
        return fail("Performance baseline version must be 1.")
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        return fail("Performance baseline must contain at least one case.")

    for index, raw_case in enumerate(cases):
        try:
            name, command, max_ms = validate_case(raw_case, index)
        except ValueError as error:
            return fail(str(error))
        start = time.perf_counter()
        try:
            completed = run_command(command)
        except (FileNotFoundError, ValueError) as error:
            return fail(f"Performance case {name} could not start: {error}")
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        if completed.returncode != 0:
            return fail(
                f"Performance case {name} failed with exit {completed.returncode}.\n"
                f"stderr:\n{completed.stderr}"
            )
        try:
            parsed = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            return fail(f"Performance case {name} did not emit valid JSON: {error}")
        scanned = parsed.get("summary", {}).get("declarations_scanned")
        expected_scanned = len(raw_case["declarations"])
        if scanned != expected_scanned:
            return fail(f"Performance case {name} scanned {scanned}, expected {expected_scanned}.")
        if elapsed_ms > max_ms:
            return fail(f"Performance case {name} took {elapsed_ms:.1f}ms, limit is {max_ms:.1f}ms.")
        print(f"{name}: {elapsed_ms:.1f}ms <= {max_ms:.1f}ms")

    print(f"Performance baseline validated for {len(cases)} case(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
