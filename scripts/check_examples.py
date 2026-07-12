from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = "Examples/HiddenPackage.lean"
EXPECTED_OUTPUT = ROOT / "Examples" / "HiddenPackage.expected.txt"


def windows_path_to_wsl(path: Path) -> str:
    resolved = str(path.resolve()).replace("\\", "/")
    if len(resolved) >= 3 and resolved[1:3] == ":/":
        return f"/mnt/{resolved[0].lower()}{resolved[2:]}"
    raise ValueError(f"cannot translate non-drive Windows path to WSL: {path}")


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    if shutil.which(command[0]) is not None:
        if os.name == "posix":
            # Elaborating the example runs interpreted metaprogram code, whose
            # recursion can overflow the default thread stack on CI runners
            # (observed as exit 139 on a hosted job whose sibling jobs passed
            # the identical command). Raise the stack limit where the platform
            # allows; macOS caps the value, hence the fallback chain.
            shell_command = " ".join(shlex.quote(part) for part in command)
            command = [
                "bash", "-c",
                "ulimit -s unlimited 2>/dev/null || ulimit -s 65500 2>/dev/null || true; "
                f"exec {shell_command}",
            ]
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


LEAN_VERSION_TOKEN = "<LEAN_VERSION>"


def live_lean_version() -> str:
    """Version string of the pinned toolchain, e.g. `4.31.0` from
    `leanprover/lean4:v4.31.0`. Matches Lean.versionString for release
    toolchains, so goldens can store a toolchain-portable token."""
    pin = (ROOT / "lean-toolchain").read_text(encoding="utf-8").strip()
    version = pin.rsplit(":", 1)[-1]
    return version[1:] if version.startswith("v") else version


def normalize_output(output: str) -> str:
    normalized = output.replace("\r\n", "\n").replace("\r", "\n")
    return normalized.replace(live_lean_version(), LEAN_VERSION_TOKEN)


def main() -> int:
    source = (ROOT / EXAMPLE).read_text(encoding="utf-8")
    required_commands = [
        "#print axioms Examples.HiddenPackage.usesCertifiedValue",
        "#assumptions Examples.HiddenPackage.usesCertifiedValue",
        "#assumptions strict Examples.HiddenPackage.usesCertifiedValue",
        "#assumptions_json Examples.HiddenPackage.usesCertifiedValue",
    ]
    missing_commands = [command for command in required_commands if command not in source]
    if missing_commands:
        print("example source is missing expected command(s):", file=sys.stderr)
        for command in missing_commands:
            print(f"- {command}", file=sys.stderr)
        return 1

    command = ["lake", "env", "lean", EXAMPLE]
    try:
        completed = run_command(command)
    except (FileNotFoundError, ValueError) as error:
        print(f"example check could not start: {error}", file=sys.stderr)
        return 1
    combined_output = normalize_output(completed.stdout + completed.stderr)
    if completed.returncode != 0:
        print(f"example check failed with exit {completed.returncode}", file=sys.stderr)
        print(combined_output, file=sys.stderr)
        return 1

    expected_output = normalize_output(EXPECTED_OUTPUT.read_text(encoding="utf-8"))
    if combined_output.strip() != expected_output.strip():
        print(f"example output differs from {EXPECTED_OUTPUT.relative_to(ROOT)}", file=sys.stderr)
        return 1

    required_fragments = [
        "'Examples.HiddenPackage.usesCertifiedValue' does not depend on any axioms",
        "target: Examples.HiddenPackage.usesCertifiedValue",
        "- pkg : package_with_prop_fields [explicit]",
        "- value : pure_data [explicit]",
        "- certified : direct_prop [explicit] flags=[binder_type_is_prop]",
        "policy_result: fail",
        '"policy_result":"fail"',
        '"primary_category":"package_with_prop_fields"',
        '"name":"certified"',
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
