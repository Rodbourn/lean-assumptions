# Baseline Mode Spec

This document records the implemented repository-agnostic baseline behavior.
Baseline mode is support-layer functionality: it runs the ordinary audit path,
renders the current result as batch JSON, and compares finding identities against
a checked-in baseline artifact. It does not re-run Lean elaboration for the
baseline file, migrate schemas, change certified classification, or change policy
semantics.

Baseline input requirements:

- the baseline is an ordinary batch JSON artifact emitted by `lean-assumptions`
- the current artifact is produced by the same CLI invocation before comparison
- baseline artifacts use the public report schema version in
  `LeanAssumptions.jsonSchemaVersion`
- schema-version mismatches are errors; baseline mode does not attempt migration
- malformed or unsupported artifacts are baseline-input errors, not successful
  comparisons

Baseline file convention:

- projects may choose any path with `--baseline <artifact.json>`
- `.lean-assumptions-baseline.json` is the recommended checked-in convention for
  repository CI
- `--update-baseline <artifact.json>` writes a fresh baseline from the current
  run and succeeds even when the file does not already exist
- the written baseline keeps only reports that contain policy findings, so it
  freezes existing debt without tracking passing declarations

Finding identity:

Two findings are the same across baseline runs exactly when all public identity
fields below match:

```text
(target, kind, category, path, type_name)
```

The identity intentionally excludes `severity`, rendered expression strings, raw
declaration types, and assumption-tree formatting. A warning/failure policy
treatment change should not churn a baseline, and unrelated rendering changes
should not invalidate debt identities. Declaration renames, path changes, finding
kind/category changes, and type-name changes are real baseline changes.

Baseline comparison statuses:

- `pass`: no new findings are present in the current run
- `improvement`: the baseline contains findings absent from the current run and
  the current run adds no findings
- `regression`: the current run contains at least one finding absent from the
  baseline

Exit codes:

- `0`: `pass`
- `0`: `improvement`
- `1`: `regression`
- `2`: missing baseline, parse failure, schema-version mismatch, argument error,
  module import error, or audit failure before comparison

Acceptance behavior:

- `--accept` updates the baseline only for `improvement`
- `--accept` does not update a baseline on `pass`
- `--accept` does not update a baseline on `regression`
- `--update-baseline <artifact.json>` always writes the current finding-bearing
  batch artifact and is intended for first-run setup or deliberate regeneration

CLI examples:

```text
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json --accept
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --update-baseline .lean-assumptions-baseline.json
```

Current boundary:

- baseline mode emits stable human-readable text output only
- the baseline artifact itself remains ordinary report schema v1 batch JSON
- no baseline-specific JSON schema is introduced
- baseline mode compares rendered audit artifacts only and does not validate
  proof axioms, sandbox execution, prove statement equivalence, infer remediation,
  or inspect historical Lean environments

Executable coverage:

- `LeanAssumptions.Baseline` implements artifact parsing, finding identity,
  comparison, status/exit-code mapping, and stable text rendering
- `LeanAssumptions.Cli` wires `--baseline`, `--accept`, and
  `--update-baseline` into the existing audit/import path
- `LeanAssumptionsTest/Unit/Baseline/Phase4.lean` checks the identity contract
- `LeanAssumptionsTest/Golden/Baseline.lean` checks pass, regression,
  improvement, and schema-mismatch behavior with golden text output
- `LeanAssumptionsTest/Integration/Cli.lean` checks public CLI baseline exit
  behavior and update/accept write-back behavior
- `scripts/check_report_schema.py` validates nested golden baseline JSON inputs
  against the existing batch report schema
