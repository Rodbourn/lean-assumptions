# lean-assumptions

[![ci](https://github.com/Rodbourn/lean-assumptions/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Rodbourn/lean-assumptions/actions/workflows/ci.yml)
[![compatibility](https://github.com/Rodbourn/lean-assumptions/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Rodbourn/lean-assumptions/actions/workflows/compatibility.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

`lean-assumptions` is a Lean 4 package and CLI for auditing assumptions that
appear in theorem and declaration statements.

It is meant to sit next to Lean's built-in axiom reporting:

```lean
#print axioms MyTheorem
#print assumptions MyTheorem
#print assumption_tree MyTheorem
#print assumption_json MyTheorem
```

`#print axioms` answers which axioms a proof term transitively depends on.
`#print assumptions` answers a different question: what assumptions are present
in the elaborated declaration type itself?

That includes assumptions carried by:

- direct `Prop` binders
- implicit, strict-implicit, and instance-implicit binders
- structures and classes with proposition-valued fields
- proof-carrying data such as `Subtype`, `Sigma`, and `PSigma`
- reducible aliases and wrapper types, subject to an explicit transparency mode

The intended users are Lean developers, library maintainers, and reviewers who
want a deterministic report of a theorem's statement-level assumption surface.
The tool is especially useful when cleaning up APIs that accidentally hide
logical assumptions inside packages, typeclasses, or aliases.

## Example

A theorem can look like it takes ordinary data while also receiving a proof
through a package argument:

```lean
structure CertifiedValue where
  value : Nat
  certified : value = value

theorem usesCertifiedValue (pkg : CertifiedValue) : pkg.value = pkg.value := rfl
```

The theorem has no direct hypothesis named `h`, but its `pkg` argument carries a
proposition-valued field. The four commands below show how this sits next to
Lean's built-in axiom view:

```lean
#print axioms Examples.HiddenPackage.usesCertifiedValue
#print assumptions Examples.HiddenPackage.usesCertifiedValue
#print assumption_tree Examples.HiddenPackage.usesCertifiedValue
#print assumption_json Examples.HiddenPackage.usesCertifiedValue
```

The first command answers the proof-dependency question:

```text
'Examples.HiddenPackage.usesCertifiedValue' does not depend on any axioms
```

The relevant output from `#print assumptions` answers the statement-surface
question:

```text
lean-assumptions report
target: Examples.HiddenPackage.usesCertifiedValue
policy_result: fail
assumption_tree:
- pkg : package_with_prop_fields [explicit]
  - value : pure_data [explicit]
  - certified : direct_prop [explicit] flags=[binder_type_is_prop]
policy_findings:
- unapproved_package_with_prop_fields severity=failure path=pkg category=package_with_prop_fields type=Examples.HiddenPackage.CertifiedValue
```

`#print assumption_tree` emits the same normalized tree in the text report.
`#print assumption_json` emits the same result as machine-readable JSON; the
relevant fields are:

```json
{
  "schema_version": "1",
  "target": "Examples.HiddenPackage.usesCertifiedValue",
  "policy_result": "fail",
  "assumption_tree": [
    {
      "name": "pkg",
      "primary_category": "package_with_prop_fields"
    }
  ]
}
```

That is the core use case: make statement-level assumptions visible even when
they are hidden behind packaging, typeclasses, aliases, or proof-carrying data.
The complete runnable version is in
[Examples/HiddenPackage.lean](Examples/HiddenPackage.lean), and the checked
current output is in
[Examples/HiddenPackage.expected.txt](Examples/HiddenPackage.expected.txt):

```text
lake env lean Examples/HiddenPackage.lean
```

## Quick Start

In a Lean file:

```lean
import LeanAssumptions
import MyProject.Theorems

#print assumptions MyProject.Theorems.target
#print assumption_tree MyProject.Theorems.target
#print assumption_json MyProject.Theorems.target
```

From the CLI:

```text
lake env lean-assumptions --module MyProject.Theorems --decl MyProject.Theorems.target --format text
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --format json
```

For iterative cleanup work, compare or cluster prior audit artifacts:

```text
lake env lean-assumptions --diff baseline-audit.json current-audit.json --format text
lake env lean-assumptions --cluster current-audit.json --format text
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json
```

## What It Guarantees

For a chosen declaration, policy, and transparency mode, `lean-assumptions`
inspects the elaborated declaration type visible in the current Lean
environment, peels surface binders, expands supported packages recursively, emits
a deterministic assumption tree, and evaluates that tree against a deterministic
policy.

Classification is by positive recognition of normalized head shapes. Unknown
or unsupported cases — including unrecognized heads, unfoldable alias heads,
and declaration surfaces that cannot be fully peeled — are reported
conservatively and do not silently pass strict policy. All false-pass classes
confirmed by the 2026-07-11 audit are closed with regression tests; see
[Audit Status](#audit-status).

Baseline mode preserves that contract for CI adoption. It compares the current
finding-bearing batch artifact against a checked-in v1 batch JSON baseline and
fails only when new finding identities appear. It does not reclassify the
baseline file, migrate schemas, validate proof axioms, or infer remediation.

## What It Does Not Do

This tool does not replace:

- `#print axioms`
- `leanchecker`
- `comparator`
- theorem-statement equivalence checking
- sandboxing or hostile-environment validation

It audits declaration statements. It does not prove that a theorem matches an
informal claim, validate proof axioms, or certify imported libraries.

## Current Status

This is an early public development checkpoint, not a finished release.

Implemented and locally verified:

- core report model, declaration inspection, binder peeling, and direct proposition detection
- recursive structure/class expansion and proof-carrying data detection
- cycle-safe unknown reporting and strict policy evaluation
- deterministic text, JSON, and batch renderers with golden snapshots
- `#print assumptions`, `#print assumption_tree`, and `#print assumption_json`
- CLI declaration inspection, declaration lists, module scans, policy files, and CI-oriented exit codes
- versioned report, batch-report, delta-report, cluster-report, and policy schemas
- delta reporting between prior/current JSON audit artifacts
- failure clustering by report-derived finding signatures
- baseline mode for freezing existing finding debt and failing CI on new findings
- doc-gen4 API documentation configuration
- cross-platform CI configuration, release-readiness checks, and a smoke-level performance baseline

Remaining partial or tracked requirements are documented in
[docs/requirements-status.md](docs/requirements-status.md). A local `v0.1.0`
prerelease tag exists as a development checkpoint. No public release has been
published, and Reservoir publication has not happened yet.

### Audit Status

An internal audit on 2026-07-11 confirmed certified-path bugs: silent
`pure_data` false passes for unrecognized statement shapes, `abbrev`-only
alias detection, an unaudited declaration surface, mislabeled transparency
semantics, false cycle reports on nested generics, and artifacts that reported
CLI-weakened policies under the unmodified `strict` label. Every confirmed
finding is now fixed with a regression test in the same change, and remaining
requirement-level work is tracked honestly in
[docs/requirements-status.md](docs/requirements-status.md).

## Design Boundary

The repository keeps its certified core in:

- `LeanAssumptions/Core`
- `LeanAssumptions/Policy`

Rendering, commands, CLI, delta reporting, clustering, baseline comparison,
docs, scripts, and CI are support layers. They should not be able to silently change certified
classification or policy decisions.

Implemented behavior, remaining gaps, and phase boundaries are documented here:

- Phase 1 spec: [docs/phase1-spec.md](docs/phase1-spec.md)
- Phase 2 spec: [docs/phase2-spec.md](docs/phase2-spec.md)
- Phase 3 spec: [docs/phase3-spec.md](docs/phase3-spec.md)
- Phase 4 spec: [docs/phase4-spec.md](docs/phase4-spec.md)
- Delta reporting spec: [docs/delta-spec.md](docs/delta-spec.md)
- Failure clustering spec: [docs/clustering-spec.md](docs/clustering-spec.md)
- Baseline mode spec: [docs/baseline-spec.md](docs/baseline-spec.md)
- Requirement tracker: [docs/requirements-status.md](docs/requirements-status.md)
- Lean API and tooling gaps: [docs/api-gaps.md](docs/api-gaps.md)

## Lean Commands

Import `LeanAssumptions` in a Lean file and use the command surface:

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
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json --accept
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --update-baseline .lean-assumptions-baseline.json
```

Audit mode requires at least one `--module` import and at least one `--decl` or `--scan-module`. It exits `0` when all audited declarations pass or warn under policy, `1` when policy evaluation fails or an audit error occurs, and `2` for argument, import, or policy-file parse errors. Batch JSON includes counts for scanned, passed, warned, failed, and unknown-bearing declarations.

Delta mode uses `--diff <baseline.json> <current.json>` and compares JSON artifacts already emitted by `lean-assumptions`. It reports added or removed declarations, policy-result changes, finding-category changes, and top-level boundary-shape changes. Delta mode exits `0` for a successful comparison and `2` for argument or artifact-parse errors. It does not re-run Lean elaboration, validate proof axioms, sandbox execution, prove statement equivalence, or suggest remediation.

Cluster mode uses `--cluster <audit.json>` and groups failing declarations from an existing single-report or batch JSON artifact. Cluster signatures use report-derived fields: finding kind, category, source class, `type_name`, and module/lane metadata only when such metadata is present in the artifact. It does not infer project-specific lanes from names and does not suggest remediation.

Baseline mode uses `--baseline <audit.json>` while running an ordinary audit. It compares current finding identities against a checked-in v1 batch JSON artifact and exits `0` for pass or improvement, `1` for regression, and `2` for missing or invalid baseline artifacts, schema mismatches, argument errors, import errors, or audit failures before comparison. `--accept` rewrites the baseline only on improvement. `--update-baseline <audit.json>` writes a fresh debt-only baseline from the current run. Baseline mode emits text output and does not introduce a new schema.

A typical downstream CI gate checks in `.lean-assumptions-baseline.json` and runs:

```text
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --baseline .lean-assumptions-baseline.json
```

Supported policy-related flags:

- `--policy <file>` reads a versioned JSON policy file. At most one `--policy`
  is accepted.
- `--allow-direct <Name>` permits an exact direct proposition binder name.
- `--allow-package <Name>` permits an exact package or proof-carrying type head.
- `--allow-typeclasses` permits typeclass assumptions.
- `--allow-unknowns` permits unknown nodes.
- `--warn-unknowns` downgrades unknown nodes to warnings.

Allow flags compose on top of the base policy regardless of argument order.
Every modification is recorded in the reported `policy_identifier` (for
example `strict+allow-package:MyProject.SafePackage`), and every artifact also
carries a `policy_digest` that identifies the effective policy semantics
independently of the label, so a weakened policy can never masquerade as the
unmodified base policy.

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

Supported transparency spellings are `none`, `reducible`, and `recursive_normalization`. With `none`, no definition head is unfolded: every alias head is reported as an `alias` node and fails strict policy unless aliases are explicitly allowed. With `reducible`, `abbrev` and `@[reducible]` heads are expanded at reducible transparency; plain `def` heads stay folded and are reported as `alias` nodes. With `recursive_normalization`, heads are normalized at default transparency to a fixed point at every inspected node. Every report carries `transparency_limited`, which is `true` whenever unexpanded alias heads remain, meaning classification depends materially on the chosen mode. Unknowns are not silently downgraded; they pass only when the policy explicitly allows or warns on them.

## CI

The repository CI uses `leanprover/lean-action`. The main build/test job is
configured as an OS matrix over `ubuntu-latest` and `macos-latest`; both targets
run the same explicit build, test, lint, leanchecker, schema, example, workflow,
and CLI smoke checks. The API-docs job runs on Ubuntu. Native Windows hosted CI
is intentionally unsupported for now; Windows users should run the package under
WSL2. A separate compatibility workflow runs weekly against
`leanprover/lean4:v4.30.0-rc2`, the toolchain currently pinned by this
repository; it does not yet test any newer stable or release-candidate
toolchain. A scheduled update workflow uses
`leanprover-community/lean-update@main` with
`update_if_modified: lean-toolchain`.

```text
lake build
lake test
lake lint
lake env leanchecker --fresh LeanAssumptions
python scripts/check_coverage_ledger.py
python scripts/check_report_schema.py
python scripts/check_policy_schema.py
python scripts/check_line_endings.py
python scripts/check_examples.py
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
- `python scripts/check_line_endings.py`
- `python scripts/check_examples.py`
- `python scripts/check_ci_workflow.py`
- `python scripts/check_performance_baseline.py`
- `python scripts/check_release_readiness.py`
- `lake env lean-assumptions --module LeanAssumptionsTest.Fixtures --decl LeanAssumptionsTest.Fixtures.packageBinder --format json --allow-package LeanAssumptionsTest.Fixtures.ProofPackage`
- `cd docbuild && DOCGEN_SRC=file lake build LeanAssumptions:docs`

The project is not finished while any requirement remains `partial` or `tracked` in the requirement tracker.
