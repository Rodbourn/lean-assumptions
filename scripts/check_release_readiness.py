from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


REQUIRED_FILES = [
    "README.md",
    "LICENSE",
    "SECURITY.md",
    "CHANGELOG.md",
    ".gitattributes",
    "lean-toolchain",
    "lakefile.lean",
    "lake-manifest.json",
    "LeanAssumptions.lean",
    "LeanAssumptions/Version.lean",
    "Examples/HiddenPackage.lean",
    "Examples/HiddenPackage.expected.txt",
    "docs/baseline-spec.md",
    "schema/report-v1.schema.json",
    "schema/batch-report-v1.schema.json",
    "schema/delta-report-v1.schema.json",
    "schema/cluster-report-v1.schema.json",
    "schema/policy-v1.schema.json",
    ".github/workflows/ci.yml",
    ".github/workflows/compatibility.yml",
    ".github/workflows/update.yml",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    "scripts/check_line_endings.py",
    "scripts/check_examples.py",
]


def fail(errors: list[str]) -> int:
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def extract(pattern: str, text: str, message: str, errors: list[str]) -> str:
    match = re.search(pattern, text)
    if match is None:
        errors.append(message)
        return ""
    return match.group(1)


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


def check_required_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        path = ROOT / relative
        require(path.exists(), f"required release-readiness file is missing: {relative}", errors)
        if path.exists():
            require(path.stat().st_size > 0, f"required release-readiness file is empty: {relative}", errors)


def check_lake_metadata(errors: list[str]) -> tuple[str, str]:
    lakefile = read("lakefile.lean")
    package_version = extract(r'version\s*:=\s*v!"([^"]+)"', lakefile, "lakefile.lean must declare a package version.", errors)
    package_name = extract(r'package\s+«?([^»\s]+)»?\s+where', lakefile, "lakefile.lean must declare a package name.", errors)
    require('description := "' in lakefile, "lakefile.lean must declare a Reservoir-facing description.", errors)
    require("keywords := #[" in lakefile, "lakefile.lean must declare Reservoir-facing keywords.", errors)
    require('license := "Apache-2.0"' in lakefile, "lakefile.lean must declare Apache-2.0 license metadata.", errors)
    require("reservoir := true" in lakefile, "lakefile.lean must opt in to Reservoir metadata with `reservoir := true`.", errors)
    require("lean_lib LeanAssumptions" in lakefile, "lakefile.lean must expose the LeanAssumptions library.", errors)
    require("lean_exe «lean-assumptions»" in lakefile, "lakefile.lean must expose the lean-assumptions executable.", errors)
    return package_name, package_version


def check_version_and_schema(package_version: str, errors: list[str]) -> None:
    version_file = read("LeanAssumptions/Version.lean")
    tool_version = extract(r'def toolVersion\s*:\s*String\s*:=\s*"([^"]+)"', version_file, "toolVersion is missing.", errors)
    report_model_version = extract(
        r'def reportModelVersion\s*:\s*String\s*:=\s*"([^"]+)"',
        version_file,
        "reportModelVersion is missing.",
        errors,
    )
    schema_version = extract(
        r'def jsonSchemaVersion\s*:\s*String\s*:=\s*"([^"]+)"',
        version_file,
        "jsonSchemaVersion is missing.",
        errors,
    )
    if package_version:
        allowed_tool_versions = {package_version, f"{package_version}-dev"}
        require(
            tool_version in allowed_tool_versions,
            f"toolVersion {tool_version!r} must match package version {package_version!r} or its -dev snapshot.",
            errors,
        )
    require(report_model_version == tool_version, "reportModelVersion must match toolVersion for this snapshot.", errors)
    require(schema_version == "1", "jsonSchemaVersion must remain 1 while schema/v1 files are public.", errors)

    report_schema = json.loads(read("schema/report-v1.schema.json"))
    batch_schema = json.loads(read("schema/batch-report-v1.schema.json"))
    delta_schema = json.loads(read("schema/delta-report-v1.schema.json"))
    cluster_schema = json.loads(read("schema/cluster-report-v1.schema.json"))
    policy_schema = json.loads(read("schema/policy-v1.schema.json"))
    require(report_schema["properties"]["schema_version"]["const"] == schema_version, "report schema version mismatch.", errors)
    require(batch_schema["properties"]["schema_version"]["const"] == schema_version, "batch schema version mismatch.", errors)
    require(delta_schema["properties"]["schema_version"]["const"] == schema_version, "delta schema version mismatch.", errors)
    require(cluster_schema["properties"]["schema_version"]["const"] == schema_version, "cluster schema version mismatch.", errors)
    require(policy_schema["properties"]["version"]["const"] == 1, "policy schema version mismatch.", errors)


def check_docs_and_governance(errors: list[str]) -> None:
    readme = read("README.md")
    changelog = read("CHANGELOG.md")
    security = read("SECURITY.md")
    issue_template = read(".github/ISSUE_TEMPLATE/bug_report.yml")
    require("This tool does not replace" in readme, "README must state non-goals.", errors)
    require("Policy Files" in readme, "README must document policy files.", errors)
    require("CI" in readme, "README must document CI integration.", errors)
    require("## Unreleased" in changelog, "CHANGELOG must keep an Unreleased section.", errors)
    require("schema" in changelog.lower(), "CHANGELOG must mention schema-affecting behavior.", errors)
    require("Misclassification bugs" in security, "SECURITY.md must name misclassification bugs as correctness incidents.", errors)
    for required in ["Minimal Reproducer", "Lean Version", "Expected Conservative Behavior", "Observed Behavior"]:
        require(required in issue_template, f"issue template must require {required}.", errors)


def tracked_release_blockers() -> list[str]:
    blockers: list[str] = []
    for line in read("docs/requirements-status.md").splitlines():
        stripped = line.strip()
        if stripped.startswith("|") and ("| partial |" in stripped or "| tracked |" in stripped):
            blockers.append(stripped)
    return blockers


def check_artifact_smoke(errors: list[str]) -> None:
    command = [
        "lake",
        "env",
        "lean-assumptions",
        "--module",
        "LeanAssumptionsTest.Fixtures",
        "--decl",
        "LeanAssumptionsTest.Fixtures.packageBinder",
        "--format",
        "json",
        "--allow-package",
        "LeanAssumptionsTest.Fixtures.ProofPackage",
    ]
    try:
        completed = run_command(command)
    except (FileNotFoundError, ValueError) as error:
        errors.append(f"release artifact smoke test could not start: {error}")
        return
    if completed.returncode != 0:
        errors.append(f"release artifact smoke test failed with exit {completed.returncode}: {completed.stderr}")
        return
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        errors.append(f"release artifact smoke test did not emit valid JSON: {error}")
        return
    summary = parsed.get("summary", {})
    require(summary.get("declarations_scanned") == 1, "release artifact smoke test must scan exactly one declaration.", errors)
    require(summary.get("declarations_passed") == 1, "release artifact smoke test must pass its allowlisted declaration.", errors)
    require(parsed.get("schema_version") == "1", "release artifact smoke test must emit schema_version 1.", errors)


def check_examples(errors: list[str]) -> None:
    command = [sys.executable, "scripts/check_examples.py"]
    try:
        completed = run_command(command)
    except (FileNotFoundError, ValueError) as error:
        errors.append(f"example validation could not start: {error}")
        return
    if completed.returncode != 0:
        errors.append(f"example validation failed with exit {completed.returncode}: {completed.stderr}")


def check_line_endings(errors: list[str]) -> None:
    command = [sys.executable, "scripts/check_line_endings.py"]
    try:
        completed = run_command(command)
    except (FileNotFoundError, ValueError) as error:
        errors.append(f"line-ending validation could not start: {error}")
        return
    if completed.returncode != 0:
        errors.append(f"line-ending validation failed with exit {completed.returncode}: {completed.stderr}")


def main() -> int:
    release_mode = "--release" in sys.argv[1:]
    unknown_args = [arg for arg in sys.argv[1:] if arg != "--release"]
    if unknown_args:
        return fail([f"unknown option: {unknown_args[0]}"])

    errors: list[str] = []
    check_required_files(errors)
    package_name, package_version = check_lake_metadata(errors)
    check_version_and_schema(package_version, errors)
    check_docs_and_governance(errors)
    check_artifact_smoke(errors)
    check_line_endings(errors)
    check_examples(errors)
    blockers = tracked_release_blockers()
    if release_mode and blockers:
        errors.append(f"release mode is blocked by {len(blockers)} partial/tracked requirement(s).")

    if errors:
        return fail(errors)

    print(f"Local release hardening checks passed for {package_name or 'unknown-package'}.")
    if blockers:
        print(f"Release remains blocked by {len(blockers)} tracked or partial requirement(s).")
    else:
        print("No tracked or partial requirements remain in docs/requirements-status.md.")
    if not release_mode:
        print("Run with --release to require zero tracked or partial requirements before a final release tag.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
