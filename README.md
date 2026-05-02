# lean-assumptions

`lean-assumptions` audits the assumption surface of elaborated Lean declaration types.

Lean already answers a different question with `#print axioms`: which axioms a proof term transitively depends on. This repository is for the theorem-statement side: binders, packaged assumptions, typeclass arguments, aliases, and proof-carrying data that appear in the elaborated declaration type itself.

Current status:

- Phase 0 package skeleton is present.
- Phase 1 certified-path work is complete for its scoped behavior: the core report model, declaration inspection, binder peeling, direct proposition detection, Phase 1 metadata, and the fixture corpus are implemented and tested.
- Phase 2 certified-path deliverables are implemented for recursive structure/class expansion, `Subtype`/`Sigma`/`PSigma` proof-carrying detection, cycle-safe unknown reporting, and strict policy evaluation.
- Phase 3 deliverables are implemented and locally verified: deterministic text/JSON renderers, golden snapshots, versioned report and policy schemas, `#print` commands, a Lake executable, policy-file parsing, declaration-list inspection, module scanning, batch summaries, CI-oriented exit codes, and doc-gen4 API docs.
- FR-016 delta reporting is implemented for comparing prior/current JSON audit artifacts, with stable text and JSON output.
- FR-017 failure clustering is implemented for grouping failing declarations in JSON audit artifacts by report-derived signatures.
- The current test driver runs through `lake test`.
- Phase 4 has started with cross-platform CI matrix configuration for Ubuntu, macOS, and Windows, a scheduled Lean release-candidate compatibility workflow, an automated Lean upgrade workflow, a smoke-level performance baseline, and local release-hardening checks for Lake/Reservoir metadata, schema/changelog consistency, and CLI artifact sanity. Hosted CI results are not locally observable.
- Actual release readiness, tagging, Reservoir publication, and any remaining `partial` requirements are tracked explicitly in [docs/requirements-status.md](docs/requirements-status.md).

This tool does not replace:

- `#print axioms`
- `leanchecker`
- `comparator`
- theorem-statement equivalence checking
- sandboxing or hostile-environment validation

Implemented behavior, remaining gaps, and phase boundaries are documented rather than implied:

- behavioral spec: [docs/phase1-spec.md](docs/phase1-spec.md)
- Phase 2 spec: [docs/phase2-spec.md](docs/phase2-spec.md)
- Phase 3 spec: [docs/phase3-spec.md](docs/phase3-spec.md)
- Phase 4 spec: [docs/phase4-spec.md](docs/phase4-spec.md)
- Delta reporting spec: [docs/delta-spec.md](docs/delta-spec.md)
- Failure clustering spec: [docs/clustering-spec.md](docs/clustering-spec.md)
- requirement tracker: [docs/requirements-status.md](docs/requirements-status.md)
- Lean API and tooling gaps: [docs/api-gaps.md](docs/api-gaps.md)

The repository keeps its certified core in:

- `LeanAssumptions/Core`
- `LeanAssumptions/Policy`

All other modules are support layers or future scaffolding until later phases land.

## Lean Commands

Import `LeanAssumptions` in a Lean file and use the Phase 3 command surface:

```lean
import LeanAssumptions
import MyProject.Theorems

#print assumptions MyProject.Theorems.target
#print assumption_tree MyProject.Theorems.target
#print assumption_json MyProject.Theorems.target
```

All three commands inspect the elaborated declaration type and evaluate the strict policy. The text commands show the normalized assumption tree, raw declaration type representation, policy result, unknown/cycle flags, tool version, Lean version, schema version, target declaration, transparency mode, and policy identifier. The JSON command emits the stable report schema. These commands do not validate proof axioms, sandbox Lean execution, or prove statement equivalence.

## CLI

The Lake executable is `lean-assumptions`:

```text
lake env lean-assumptions --module MyProject.Theorems --decl MyProject.Theorems.target --format text
lake env lean-assumptions --module MyProject.Theorems --decl MyProject.Theorems.target --format json --policy policy.json
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --format json
lake env lean-assumptions --diff baseline-audit.json current-audit.json --format text
lake env lean-assumptions --diff baseline-audit.json current-audit.json --format json
lake env lean-assumptions --cluster current-audit.json --format text
lake env lean-assumptions --cluster current-audit.json --format json
```

Audit mode requires at least one `--module` import and at least one `--decl` or `--scan-module`. It exits `0` when all audited declarations pass or warn under policy, `1` when policy evaluation fails or an audit error occurs, and `2` for argument, import, or policy-file parse errors. Batch JSON includes counts for scanned, passed, warned, failed, and unknown-bearing declarations.

Delta mode uses `--diff <baseline.json> <current.json>` and compares JSON artifacts already emitted by `lean-assumptions`. It reports added or removed declarations, policy-result changes, finding-category changes, and top-level boundary-shape changes. Delta mode exits `0` for a successful comparison and `2` for argument or artifact-parse errors. It does not re-run Lean elaboration, validate proof axioms, sandbox execution, prove statement equivalence, or suggest remediation.

Cluster mode uses `--cluster <audit.json>` and groups failing declarations from an existing single-report or batch JSON artifact. Cluster signatures use report-derived fields: finding kind, category, source class, `type_name`, and module/lane metadata only when such metadata is present in the artifact. It does not infer project-specific lanes from names and does not suggest remediation.

Supported policy-related flags:

- `--policy <file>` reads a versioned JSON policy file.
- `--allow-direct <Name>` permits an exact direct proposition binder name.
- `--allow-package <Name>` permits an exact package or proof-carrying type head.
- `--allow-typeclasses` permits typeclass assumptions.
- `--allow-unknowns` permits unknown nodes.
- `--warn-unknowns` downgrades unknown nodes to warnings.

## Policy Files

Policy files use `schema/policy-v1.schema.json`. Exact-name matching is the default; broader prefix matching must be explicit.

```json
{
  "version": 1,
  "identifier": "example-policy",
  "transparency_mode": "none",
  "permit_direct_props": ["MyProject.AllowedHyp"],
  "permit_package_types": [{"prefix": "MyProject.SafePackage"}],
  "typeclass_policy": "fail",
  "unknown_policy": "fail"
}
```

Supported transparency spellings are `none`, `reducible`, and `recursive_normalization`. With `none`, reducible aliases are reported as `alias` nodes and fail strict policy unless aliases are explicitly allowed. With `reducible`, abbreviation heads are expanded enough to inspect the exposed package. With `recursive_normalization`, the project normalizer repeatedly applies reducible-head normalization at inspected nodes. Unknowns are not silently downgraded; they pass only when the policy explicitly allows or warns on them.

## CI

The repository CI uses `leanprover/lean-action`. The main build/test job is
configured as an OS matrix over `ubuntu-latest`, `macos-latest`, and
`windows-latest`; the API-docs job runs on Ubuntu. A separate compatibility
workflow runs weekly against `leanprover/lean4:v4.30.0-rc2`, the current Lean
release-candidate toolchain used by this repository. A scheduled update
workflow uses `leanprover-community/lean-update@main` with
`update_if_modified: lean-toolchain`.

```text
lake build
lake test
lake lint
lake env leanchecker --fresh LeanAssumptions
python scripts/check_coverage_ledger.py
python scripts/check_report_schema.py
python scripts/check_policy_schema.py
python scripts/check_ci_workflow.py
python scripts/check_performance_baseline.py
python scripts/check_release_readiness.py
lake env lean-assumptions --module LeanAssumptionsTest.Fixtures --decl LeanAssumptionsTest.Fixtures.packageBinder --format json --allow-package LeanAssumptionsTest.Fixtures.ProofPackage
cd docbuild && DOCGEN_SRC=file lake build LeanAssumptions:docs
```

Current local verification:

- `lake build`
- `lake test`
- `lake lint`
- `lake env leanchecker --fresh LeanAssumptions`
- `python scripts/check_coverage_ledger.py`
- `python scripts/check_report_schema.py`
- `python scripts/check_policy_schema.py`
- `python scripts/check_ci_workflow.py`
- `python scripts/check_performance_baseline.py`
- `python scripts/check_release_readiness.py`
- `lake env lean-assumptions --module LeanAssumptionsTest.Fixtures --decl LeanAssumptionsTest.Fixtures.packageBinder --format json --allow-package LeanAssumptionsTest.Fixtures.ProofPackage`
- `cd docbuild && DOCGEN_SRC=file lake build LeanAssumptions:docs`

The project is not finished while any requirement remains `partial` or `tracked` in the requirement tracker.
