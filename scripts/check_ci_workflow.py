from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

# Pinned action revisions; update the SHA and the comment tag together.
CHECKOUT_SHA = "93cb6efe18208431cddfb8368fd83d5badbf9bfd"  # actions/checkout v5
SETUP_PYTHON_SHA = "a26af69be951a213d495a4c3e4e4022e16d87065"  # actions/setup-python v5
LEAN_ACTION_SHA = "38fbc41a8c28c4cbaec22d7f7de508ec2e7c0dd9"  # leanprover/lean-action v1
LEAN_UPDATE_SHA = "6f7b598c3255645e06f5d31f9f77b7440fc16451"  # leanprover-community/lean-update v0.12.0
UPLOAD_ARTIFACT_SHA = "ea165f8d65b6e75b540449e92b4886f43607fa02"  # actions/upload-artifact v4
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
COMPATIBILITY_WORKFLOW = ROOT / ".github" / "workflows" / "compatibility.yml"
UPDATE_WORKFLOW = ROOT / ".github" / "workflows" / "update.yml"
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    errors: list[str] = []

    require(f"uses: actions/checkout@{CHECKOUT_SHA}" in text, "CI must pin actions/checkout by commit SHA.", errors)
    require(f"uses: leanprover/lean-action@{LEAN_ACTION_SHA}" in text, "CI must pin leanprover/lean-action by commit SHA.", errors)
    require("permissions:" in text and "contents: read" in text, "CI must declare least-privilege permissions.", errors)
    require("concurrency:" in text, "CI must declare a concurrency group.", errors)
    require("shell: bash" in text, "CI run steps must use Bash for cross-platform Lean toolchain PATH consistency.", errors)
    for lean_action_input in ["build: false", "test: false", "lint: false"]:
        require(
            lean_action_input in text,
            f"CI must disable lean-action auto gate `{lean_action_input}` and run explicit gates instead.",
            errors,
        )
    require("strategy:" in text and "matrix:" in text, "CI must use an OS matrix.", errors)
    for runner in ["ubuntu-latest", "macos-latest"]:
        require(runner in text, f"CI matrix must include {runner}.", errors)
    require("windows-latest" not in text, "Windows CI is intentionally disabled until native hosted-runner behavior is hardened.", errors)

    required_commands = [
        "lake build",
        "lake test",
        "lake lint",
        "lake env leanchecker --fresh LeanAssumptions",
        "python3 scripts/check_coverage_ledger.py",
        "python3 scripts/check_report_schema.py",
        "python3 scripts/check_policy_schema.py",
        "python3 scripts/check_line_endings.py",
        "python3 scripts/check_examples.py",
        "python3 scripts/check_performance_baseline.py",
        "python3 scripts/check_release_readiness.py",
        "lake env lean-assumptions --module LeanAssumptionsTest.Fixtures",
        "lake build LeanAssumptions:docs",
    ]
    require(
        "python scripts/" not in text,
        "CI must invoke checker scripts with python3; bare `python` is absent on macOS runners.",
        errors,
    )
    for command in required_commands:
        require(command in text, f"CI must run `{command}`.", errors)

    require("DOCGEN_SRC: file" in text, "CI docs build must set DOCGEN_SRC=file.", errors)
    require(
        f"uses: actions/upload-artifact@{UPLOAD_ARTIFACT_SHA}" in text,
        "CI must upload the performance timing report as a pinned-artifact step.",
        errors,
    )
    require(
        re.search(r"runs-on:\s*\$\{\{\s*matrix\.os\s*\}\}", text) is not None,
        "CI build/test job must run on matrix.os.",
        errors,
    )
    require(
        len(re.findall(r"lake build LeanAssumptions lean-assumptions LeanAssumptionsTest\.Fixtures", text)) >= 2,
        "Performance and release-readiness jobs must build the LeanAssumptions library (imported by the CLI at runtime), the CLI executable, and smoke fixtures before running CLI smoke checks.",
        errors,
    )

    if COMPATIBILITY_WORKFLOW.exists():
        compatibility = COMPATIBILITY_WORKFLOW.read_text(encoding="utf-8")
    else:
        compatibility = ""
        errors.append("Scheduled Lean RC compatibility workflow is missing.")

    require("schedule:" in compatibility, "Compatibility workflow must run on a schedule.", errors)
    require("workflow_dispatch:" in compatibility, "Compatibility workflow must be manually runnable.", errors)
    for channel in ["stable", "beta"]:
        require(
            channel in compatibility,
            f"Compatibility workflow must test the Lean {channel} channel so the forward signal never goes stale.",
            errors,
        )
    require(
        "leanprover/lean4:%s" in compatibility or "leanprover/lean4:${{ matrix.channel }}" in compatibility
            or "matrix.channel" in compatibility,
        "Compatibility workflow must select toolchains through an elan channel matrix.",
        errors,
    )
    require(
        f"uses: actions/checkout@{CHECKOUT_SHA}" in compatibility,
        "Compatibility workflow must pin actions/checkout by commit SHA.",
        errors,
    )
    require(
        f"uses: leanprover/lean-action@{LEAN_ACTION_SHA}" in compatibility,
        "Compatibility workflow must pin leanprover/lean-action by commit SHA.",
        errors,
    )
    require(
        "shell: bash" in compatibility,
        "Compatibility workflow run steps must use Bash for Lean toolchain PATH consistency.",
        errors,
    )
    for lean_action_input in ["build: false", "test: false", "lint: false"]:
        require(
            lean_action_input in compatibility,
            f"Compatibility workflow must disable lean-action auto gate `{lean_action_input}` and run explicit gates instead.",
            errors,
        )
    for command in [
        "lake build",
        "lake test",
        "lake lint",
        "lake env leanchecker --fresh LeanAssumptions",
    ]:
        require(command in compatibility, f"Compatibility workflow must run `{command}`.", errors)

    if UPDATE_WORKFLOW.exists():
        update = UPDATE_WORKFLOW.read_text(encoding="utf-8")
    else:
        update = ""
        errors.append("Automated Lean upgrade workflow is missing.")

    require("schedule:" in update, "Update workflow must run on a schedule.", errors)
    require("workflow_dispatch:" in update, "Update workflow must be manually runnable.", errors)
    require(f"uses: actions/checkout@{CHECKOUT_SHA}" in update, "Update workflow must pin actions/checkout by commit SHA.", errors)
    require("contents: write" in update, "Update workflow must be allowed to write branch contents.", errors)
    require("pull-requests: write" in update, "Update workflow must be allowed to open pull requests.", errors)
    require("issues: write" in update, "Update workflow must be allowed to open failure issues.", errors)
    require(
        f"uses: leanprover-community/lean-update@{LEAN_UPDATE_SHA}" in update,
        "Update workflow must pin leanprover-community/lean-update by commit SHA (never a mutable ref with write permissions).",
        errors,
    )
    require(
        "lean-update@main" not in update,
        "Update workflow must not reference the mutable lean-update@main.",
        errors,
    )
    require(
        "update_if_modified: lean-toolchain" in update,
        "Update workflow must only create Lean-version PRs when lean-toolchain changes.",
        errors,
    )
    for command in [
        "python3 scripts/check_report_schema.py",
        "python3 scripts/check_policy_schema.py",
        "python3 scripts/check_ci_workflow.py",
    ]:
        require(command in update, f"Update workflow must run `{command}`.", errors)
    require(
        'CHECK_REPORT_SCHEMA_SKIP_FRESH: "1"' in update,
        "Update workflow must explicitly skip fresh-artifact validation (no built CLI there); the skip must be visible in the workflow.",
        errors,
    )
    for workflow_text, workflow_name in [(text, "CI"), (update, "Update")]:
        require(
            "pip install jsonschema" in workflow_text,
            f"{workflow_name} workflow must install jsonschema before running schema validators.",
            errors,
        )

    if RELEASE_WORKFLOW.exists():
        release = RELEASE_WORKFLOW.read_text(encoding="utf-8")
    else:
        release = ""
        errors.append("Tag-triggered release workflow is missing.")
    require('- "v*"' in release, "Release workflow must trigger on v-prefixed tags.", errors)
    require(
        "python3 scripts/check_release_readiness.py --release" in release,
        "Release workflow must run release-readiness in --release mode.",
        errors,
    )
    require(
        f"uses: actions/checkout@{CHECKOUT_SHA}" in release,
        "Release workflow must pin actions/checkout by commit SHA.",
        errors,
    )
    for command in ["lake build", "lake test", "lake lint",
                    "lake env leanchecker --fresh LeanAssumptions"]:
        require(command in release, f"Release workflow must run `{command}`.", errors)

    if errors:
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1

    print("CI workflow validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
