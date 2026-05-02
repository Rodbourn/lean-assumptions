# Phase 4 Behavioral Spec

This document records Phase 4 hardening and release behavior as it becomes
executable. It is not a claim that Phase 4 is complete.

Implemented CI hardening behavior:

- `.github/workflows/ci.yml` uses `leanprover/lean-action`
- the main build/test job runs on an explicit OS matrix:
  `ubuntu-latest`, `macos-latest`, and `windows-latest`
- the matrix job runs `lake build`, `lake test`, `lake lint`, and
  `lake env leanchecker --fresh LeanAssumptions`
- the matrix job validates the coverage ledger, report schema, policy schema,
  and CI workflow shape
- the matrix job smoke-tests the CLI executable against a fixture declaration
- the API-docs job runs `DOCGEN_SRC=file lake build LeanAssumptions:docs` from
  `docbuild/`
- `.github/workflows/compatibility.yml` runs weekly and by manual dispatch
- the compatibility workflow pins the current release-candidate toolchain,
  `leanprover/lean4:v4.30.0-rc2`
- the compatibility workflow runs `lake build`, `lake test`, `lake lint`, and
  `lake env leanchecker --fresh LeanAssumptions`
- `.github/workflows/update.yml` runs weekly and by manual dispatch
- the update workflow uses `leanprover-community/lean-update@main`
- the update workflow is configured with `update_if_modified: lean-toolchain`
  so Lean-version update PRs are only created when the toolchain changes
- the update workflow runs the repository-specific coverage, report-schema,
  policy-schema, and CI-workflow validators after `lean-update`
- `LeanAssumptionsTest/Performance/baseline.json` records a smoke-level
  performance baseline for representative CLI audits
- `scripts/check_performance_baseline.py` validates each performance case by
  running the public CLI, requiring valid JSON output, requiring the expected
  declaration count, and checking a broad elapsed-time ceiling
- the CI workflow includes a dedicated Ubuntu `performance-baseline` job
- `lakefile.lean` includes local Reservoir-facing package metadata: version,
  description, keywords, Apache-2.0 license metadata, and `reservoir := true`
- `scripts/check_release_readiness.py` validates local release-hardening
  prerequisites: required governance files, Lake/Reservoir metadata,
  version/schema consistency, changelog/security/issue-template coverage, and a
  JSON CLI artifact smoke test
- `scripts/check_release_readiness.py --release` is intentionally stricter: it
  fails while any `partial` or `tracked` requirement remains in
  `docs/requirements-status.md`
- the CI workflow includes a dedicated Ubuntu `release-readiness` job running
  the non-release local validator

Current Phase 4 boundary:

- hosted CI execution is not locally observable from this workspace
- local Reservoir metadata and release artifact sanity checks are implemented,
  but actual Reservoir publication is not
- release mode remains blocked while partial/tracked requirements are present
- no tagged release has been cut

The corresponding local validators are:

```text
python scripts/check_ci_workflow.py
python scripts/check_performance_baseline.py
python scripts/check_release_readiness.py
```
