# Phase 3 Behavioral Spec

This document records Phase 3 behavior as it becomes executable. It is not a
claim that Phase 3 is complete.

Implemented rendering behavior:

- `LeanAssumptions.Render.renderText` renders a stable human-readable report from a core report plus policy evaluation
- `LeanAssumptions.Render.renderJsonString` renders stable minified JSON plus a trailing newline
- text and JSON artifacts include tool version, Lean version, schema version, report-model version, target declaration, declaration kind, transparency mode, policy identifier, policy result, unknown status, and cycle status
- renderers include a deterministic assumption tree and policy findings
- renderers include a deterministic notation-resistant declaration-type representation
- generated local fvar identifiers are intentionally erased from rendered expression strings because they are not reproducible report data
- text and JSON renderers state limitations: declaration-type audit only, no proof-axiom validation, no sandboxing, no theorem-statement equivalence checking
- golden text and JSON snapshots cover the current renderer contract
- `schema/report-v1.schema.json` records the current JSON report schema
- `schema/batch-report-v1.schema.json` records the current batch JSON schema
- `schema/delta-report-v1.schema.json` records the current delta JSON schema
- `schema/cluster-report-v1.schema.json` records the current failure-cluster JSON schema
- `scripts/check_report_schema.py` validates single-report, batch, delta, and cluster golden JSON against the local schemas using only Python standard-library facilities

Implemented command behavior:

- `#print assumptions <decl>` renders the strict-policy text report for a declaration
- `#print assumption_tree <decl>` renders the strict-policy normalized assumption tree inside the same text report format
- `#print assumption_json <decl>` renders the strict-policy JSON report
- command outputs state tool version, Lean version, schema version, target declaration, transparency mode, policy identifier, unknown status, cycle status, raw declaration type, and limitations
- command adapters are support-layer code and delegate classification to `LeanAssumptions.Core`, policy evaluation to `LeanAssumptions.Policy`, and output to `LeanAssumptions.Render`

Examples:

```lean
import LeanAssumptions
import MyProject.Theorems

#print assumptions MyProject.Theorems.target
#print assumption_tree MyProject.Theorems.target
#print assumption_json MyProject.Theorems.target
```

Implemented CLI behavior:

- `lake env lean-assumptions --module <Module> --decl <Name>` inspects one declaration
- repeated `--decl <Name>` inspects a declaration list in request order
- `--scan-module <Module>` inspects declarations imported from that exact module index in deterministic dotted-name order
- `--format text` emits batch text output
- `--format json` emits batch JSON output
- exit code `0` means all audited declarations passed or warned under policy
- exit code `1` means policy failure or audit error
- exit code `2` means argument, import, or policy-file parse failure
- `--diff <baseline.json> <current.json>` compares two already-rendered JSON audit artifacts without importing Lean modules
- diff mode supports `--format text` and `--format json`
- diff mode exits `0` for a successful comparison and `2` for argument or artifact-parse failures
- diff mode rejects mixed audit and policy options instead of silently ignoring them
- `--cluster <audit.json>` groups failing declarations in an already-rendered JSON audit artifact without importing Lean modules
- cluster mode supports `--format text` and `--format json`
- cluster mode exits `0` for a successful clustering run and `2` for argument or artifact-parse failures
- cluster mode rejects mixed audit, diff, and policy options instead of silently ignoring them
- integration checks may run the CLI support path against an already imported
  Lean environment to avoid repeated module-import cost; the executable path
  still imports modules from `--module` arguments

Examples:

```text
lake env lean-assumptions --module MyProject.Theorems --decl MyProject.Theorems.target --format text
lake env lean-assumptions --module MyProject.Theorems --decl MyProject.Theorems.target --format json --policy policy.json
lake env lean-assumptions --module MyProject.Theorems --scan-module MyProject.Theorems --format json
lake env lean-assumptions --diff baseline-audit.json current-audit.json --format text
lake env lean-assumptions --diff baseline-audit.json current-audit.json --format json
lake env lean-assumptions --cluster current-audit.json --format text
lake env lean-assumptions --cluster current-audit.json --format json
```

Implemented policy-file behavior:

- `schema/policy-v1.schema.json` records the current policy-file schema
- `scripts/check_policy_schema.py` validates committed policy fixtures against that schema contract
- policy files require `"version": 1`
- `identifier` defaults to `"policy-file"` if omitted
- `transparency_mode` defaults to `"none"` if omitted
- CLI inspection uses the policy transparency mode when producing the core report, so a `"reducible"` policy inspects reducible aliases under a reducible report rather than producing a transparency mismatch
- `permit_direct_props` and `permit_package_types` accept exact names as strings, `{ "exact": "Name" }`, or explicit `{ "prefix": "Name" }` patterns
- `typeclass_policy` and `unknown_policy` accept `allow`, `warn`, or `fail`, and default to `fail`

Example:

```json
{
  "version": 1,
  "identifier": "example-policy",
  "transparency_mode": "none",
  "permit_direct_props": [],
  "permit_package_types": ["MyProject.SafePackage"],
  "typeclass_policy": "fail",
  "unknown_policy": "fail"
}
```

Implemented batch behavior:

- batch text appends `batch_summary` lines after reports
- batch JSON includes top-level tool, Lean, policy, schema, and transparency metadata
- batch JSON includes counts for declarations scanned, passed, warned, failed, and declarations with unknown nodes
- batch JSON embeds the deterministic single-report objects under `reports`

Implemented delta behavior:

- delta mode accepts single-report or batch JSON artifacts
- declarations are compared by stable target name
- output reports added declarations, removed declarations, policy-result changes, policy-finding category changes, and top-level boundary-shape changes
- top-level boundary shape uses each top-level assumption-tree node's name, binder kind, primary category, and rendered binder type
- text and JSON delta outputs are deterministic and have golden snapshots
- delta output states that it compares rendered artifacts only and does not re-run Lean elaboration, validate proof axioms, sandbox execution, prove theorem-statement equivalence, or suggest remediation

Implemented cluster behavior:

- cluster mode accepts single-report or batch JSON artifacts
- declarations with `policy_result` `fail` or `audit_error` are considered failing declarations
- findings with `severity` `failure` or `audit_error` are clustered as failing findings
- cluster signatures use finding kind, category, source class, `type_name`, and module/lane metadata when present
- missing module/lane metadata is emitted as `null`/`none`; no project-specific naming convention is inferred
- declarations inside each cluster are sorted by target name
- clusters are sorted by descending declaration count, then by signature
- text and JSON cluster outputs are deterministic and have golden snapshots
- cluster output states that it clusters rendered artifacts only and does not re-run Lean elaboration, validate proof axioms, sandbox execution, prove theorem-statement equivalence, infer project-specific cleanup lanes, or suggest remediation

Current Phase 3 boundary:

- hosted CI execution is not locally validated
- cross-platform CI configuration is owned by Phase 4
- performance benchmarks remain scaffolded for Phase 4

The corresponding tests and validators currently are:

- `LeanAssumptionsTest/Golden/Phase3.lean`
- `LeanAssumptionsTest/Golden/Delta.lean`
- `LeanAssumptionsTest/Golden/Cluster.lean`
- `LeanAssumptionsTest/Integration/Commands.lean`
- `LeanAssumptionsTest/Integration/Cli.lean`
- `LeanAssumptionsTest/Golden/packageBinder.txt`
- `LeanAssumptionsTest/Golden/packageBinder.json`
- `LeanAssumptionsTest/Golden/packageBinder-batch.json`
- `LeanAssumptionsTest/Golden/delta-report.txt`
- `LeanAssumptionsTest/Golden/delta-report.json`
- `LeanAssumptionsTest/Golden/cluster-report.txt`
- `LeanAssumptionsTest/Golden/cluster-report.json`
- `python scripts/check_report_schema.py`
- `python scripts/check_policy_schema.py`
- `cd docbuild && DOCGEN_SRC=file lake build LeanAssumptions:docs`
