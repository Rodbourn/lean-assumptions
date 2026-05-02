from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
COMPATIBILITY_WORKFLOW = ROOT / ".github" / "workflows" / "compatibility.yml"
UPDATE_WORKFLOW = ROOT / ".github" / "workflows" / "update.yml"
CURRENT_RC_TOOLCHAIN = "leanprover/lean4:v4.30.0-rc2"


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    errors: list[str] = []

    require("uses: leanprover/lean-action@v1" in text, "CI must use leanprover/lean-action@v1.", errors)
    require("strategy:" in text and "matrix:" in text, "CI must use an OS matrix.", errors)
    for runner in ["ubuntu-latest", "macos-latest", "windows-latest"]:
        require(runner in text, f"CI matrix must include {runner}.", errors)

    required_commands = [
        "lake build",
        "lake test",
        "lake lint",
        "lake env leanchecker --fresh LeanAssumptions",
        "python scripts/check_coverage_ledger.py",
        "python scripts/check_report_schema.py",
        "python scripts/check_policy_schema.py",
        "python scripts/check_performance_baseline.py",
        "python scripts/check_release_readiness.py",
        "lake env lean-assumptions --module LeanAssumptionsTest.Fixtures",
        "lake build LeanAssumptions:docs",
    ]
    for command in required_commands:
        require(command in text, f"CI must run `{command}`.", errors)

    require("DOCGEN_SRC: file" in text, "CI docs build must set DOCGEN_SRC=file.", errors)
    require(
        re.search(r"runs-on:\s*\$\{\{\s*matrix\.os\s*\}\}", text) is not None,
        "CI build/test job must run on matrix.os.",
        errors,
    )

    if COMPATIBILITY_WORKFLOW.exists():
        compatibility = COMPATIBILITY_WORKFLOW.read_text(encoding="utf-8")
    else:
        compatibility = ""
        errors.append("Scheduled Lean RC compatibility workflow is missing.")

    require("schedule:" in compatibility, "Compatibility workflow must run on a schedule.", errors)
    require("workflow_dispatch:" in compatibility, "Compatibility workflow must be manually runnable.", errors)
    require(CURRENT_RC_TOOLCHAIN in compatibility, f"Compatibility workflow must test {CURRENT_RC_TOOLCHAIN}.", errors)
    require("uses: leanprover/lean-action@v1" in compatibility, "Compatibility workflow must use leanprover/lean-action@v1.", errors)
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
    require("contents: write" in update, "Update workflow must be allowed to write branch contents.", errors)
    require("pull-requests: write" in update, "Update workflow must be allowed to open pull requests.", errors)
    require("issues: write" in update, "Update workflow must be allowed to open failure issues.", errors)
    require(
        "uses: leanprover-community/lean-update@main" in update,
        "Update workflow must use leanprover-community/lean-update@main.",
        errors,
    )
    require(
        "update_if_modified: lean-toolchain" in update,
        "Update workflow must only create Lean-version PRs when lean-toolchain changes.",
        errors,
    )
    for command in [
        "python scripts/check_coverage_ledger.py",
        "python scripts/check_report_schema.py",
        "python scripts/check_policy_schema.py",
        "python scripts/check_ci_workflow.py",
    ]:
        require(command in update, f"Update workflow must run `{command}`.", errors)

    if errors:
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1

    print("CI workflow validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
