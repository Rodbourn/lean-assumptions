from __future__ import annotations

import json
import os
import shlex
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "LeanAssumptionsTest" / "Performance" / "baseline.json"
REPORT = ROOT / ".lake" / "build" / "lean-assumptions-test" / "performance-report.json"


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


def validate_case(case: Any, index: int) -> tuple[str, list[str], float, float]:
    if not isinstance(case, dict):
        raise ValueError(f"cases[{index}] must be an object")
    name = require_string(case.get("name"), f"cases[{index}].name")
    command = command_for(case)
    max_ms = require_positive_number(case.get("max_ms"), f"cases[{index}].max_ms")
    reference_ms = require_positive_number(case.get("reference_ms"), f"cases[{index}].reference_ms")
    return name, command, max_ms, reference_ms


def main() -> int:
    if not BASELINE.exists():
        return fail(f"Missing performance baseline: {BASELINE.relative_to(ROOT).as_posix()}")

    data = json.loads(BASELINE.read_text(encoding="utf-8"))
    if data.get("version") != 2:
        return fail("Performance baseline version must be 2.")
    runs = data.get("runs", 3)
    if not isinstance(runs, int) or runs < 1:
        return fail("Performance baseline `runs` must be a positive integer.")
    regression_factor = require_positive_number(
        data.get("regression_factor", 5), "regression_factor"
    )
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        return fail("Performance baseline must contain at least one case.")

    report_cases: list[dict[str, Any]] = []
    for index, raw_case in enumerate(cases):
        try:
            name, command, max_ms, reference_ms = validate_case(raw_case, index)
        except ValueError as error:
            return fail(str(error))
        samples_ms: list[float] = []
        for _ in range(runs):
            start = time.perf_counter()
            try:
                completed = run_command(command)
            except (FileNotFoundError, ValueError) as error:
                return fail(f"Performance case {name} could not start: {error}")
            samples_ms.append((time.perf_counter() - start) * 1000.0)
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
                return fail(
                    f"Performance case {name} scanned {scanned}, expected {expected_scanned}."
                )
        median_ms = statistics.median(samples_ms)
        regression_limit_ms = reference_ms * regression_factor
        report_cases.append({
            "name": name,
            "samples_ms": [round(sample, 1) for sample in samples_ms],
            "median_ms": round(median_ms, 1),
            "reference_ms": reference_ms,
            "regression_limit_ms": regression_limit_ms,
            "max_ms": max_ms,
        })
        if median_ms > max_ms:
            return fail(
                f"Performance case {name} median {median_ms:.1f}ms exceeds the "
                f"absolute ceiling {max_ms:.1f}ms."
            )
        if median_ms > regression_limit_ms:
            return fail(
                f"Performance case {name} median {median_ms:.1f}ms exceeds "
                f"{regression_factor:g}x the recorded reference {reference_ms:.1f}ms — "
                "a performance regression. Investigate before adjusting the reference."
            )
        print(
            f"{name}: median {median_ms:.1f}ms over {runs} run(s) "
            f"(reference {reference_ms:.1f}ms, regression limit {regression_limit_ms:.1f}ms, "
            f"ceiling {max_ms:.1f}ms)"
        )

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        json.dumps({"version": 2, "runs": runs, "cases": report_cases}, indent=1) + "\n",
        encoding="utf-8",
    )
    print(
        f"Performance baseline validated for {len(cases)} case(s); "
        f"timing report written to {REPORT.relative_to(ROOT).as_posix()}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
