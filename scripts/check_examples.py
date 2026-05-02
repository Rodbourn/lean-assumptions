from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = "Examples/HiddenPackage.lean"


def windows_path_to_wsl(path: Path) -> str:
    resolved = str(path.resolve()).replace("\\", "/")
    if len(resolved) >= 3 and resolved[1:3] == ":/":
        return f"/mnt/{resolved[0].lower()}{resolved[2:]}"
    raise ValueError(f"cannot translate non-drive Windows path to WSL: {path}")


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
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


def main() -> int:
    command = ["lake", "env", "lean", EXAMPLE]
    try:
        completed = run_command(command)
    except (FileNotFoundError, ValueError) as error:
        print(f"example check could not start: {error}", file=sys.stderr)
        return 1
    combined_output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        print(f"example check failed with exit {completed.returncode}", file=sys.stderr)
        print(combined_output, file=sys.stderr)
        return 1

    required_fragments = [
        "target: Examples.HiddenPackage.usesCertifiedValue",
        "- pkg : package_with_prop_fields [explicit]",
        "- value : pure_data [explicit]",
        "- certified : direct_prop [explicit] flags=[binder_type_is_prop]",
        "policy_result: fail",
        "limitations: audits elaborated declaration types only",
    ]
    missing = [fragment for fragment in required_fragments if fragment not in combined_output]
    if missing:
        print("example output is missing expected fragment(s):", file=sys.stderr)
        for fragment in missing:
            print(f"- {fragment}", file=sys.stderr)
        return 1

    print(f"Example validated: {EXAMPLE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
