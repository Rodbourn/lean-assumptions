# Requirement Status

This tracker exists so deferred project requirements stay explicit.

Status labels:

- `done`: implemented and validated for the currently scoped phase
- `partial`: scaffolded or modeled, but not fully implemented or not fully validated
- `tracked`: explicitly deferred to a later phase

## Phases

- Phase 0 deliverables: `done`
- Phase 1 deliverables: `done` and locally verified
- Phase 2 deliverables: `done` for the trusted core/policy scope
- Phase 3 deliverables: `done` and locally verified
- Phase 4 deliverables: `done` and locally verified

The project is not finished while any requirement or verification gate below is
`partial` or `tracked`. Rows whose notes name an operational boundary (hosted
CI execution, Reservoir publication) state exactly what begins with the first
public push; those boundaries are operator actions, not open engineering work.

## Functional Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| FR-001 declaration inspection | done | Implemented for named declarations visible in the current environment, with normalized declaration kinds. |
| FR-002 binder peeling | done | Implemented for all outer `forall` binders with explicit, implicit, strict implicit, and instance-implicit kinds preserved in order. |
| FR-003 direct proposition detection | done | Implemented conservatively for non-instance binders that are propositions or range over `Prop` at the outer surface, with separate secondary flags for proof hypotheses and `Prop` quantifiers. |
| FR-004 structure and class expansion | done | Recursive structure/class expansion is implemented and tested for direct, nested, class, and cyclic package fixtures. |
| FR-005 proof-carrying data detection | done | Required `Subtype`, `Sigma`, `PSigma`, and proposition-bearing structure package cases are implemented and tested. |
| FR-006 alias transparency policy | done | The three modes are operationally distinct and mode-pinned at every reduction site: `none` never unfolds definition heads, `reducible` unfolds only `abbrev` and `@[reducible]` heads at reducible transparency, and `recursive_normalization` normalizes at default transparency to a fixed point. Heads that survive normalization are reported as `alias` nodes, and every artifact carries a `transparency_limited` signal that is `true` whenever classification depends materially on the chosen mode. |
| FR-007 cycle detection | done | Recursive expansion is fuel-bounded and cycle-safe. Cycle detection compares normalized type instances rather than head names, so nested same-head generics such as `Nat × Nat × Nat` expand normally while genuinely cyclic package graphs truncate explicitly, emit `unknown`, set `cyclesTruncated`, and fail strict policy. |
| FR-008 deterministic tree output | done | The internal `AssumptionReport` tree, renderers, commands, CLI declaration lists, and module scans use deterministic binder, field, request, or sorted dotted-name order. |
| FR-009 human-facing commands | done | `#assumptions` (hidden-surface default), `#assumptions strict`, and `#assumptions_json` are implemented and exercised by integration tests; the pre-adoption rename away from core's `#print` syntax is recorded in the compatibility policy. The backward-compatibility policy for command names, CLI flags, and schemas is documented in `docs/compatibility-policy.md`. |
| FR-010 CLI | done | The `lean-assumptions` executable supports one declaration, declaration lists, module scans, text/JSON output, and nonzero exit codes for policy or audit failure. |
| FR-011 policy files | done | The CLI accepts versioned JSON policy files with exact/prefix allowlists, typeclass treatment, unknown treatment, and transparency mode; schema and fixture validation are present. |
| FR-012 conservative failure mode | done | Classification is by positive head recognition: unrecognized binder-type head shapes emit `unknown` and fail strict policy, unfoldable definition heads report `alias` under `none` transparency, `let` wrappers reduce structurally, non-structure inductives are scanned constructor by constructor, and function types classify through their result type. Declaration surfaces that stop at an alias-headed or unpeelable remainder report an explicit `result` surface node that fails strict policy. |
| FR-013 raw theorem-surface visibility | done | Text, JSON, command, and CLI outputs include deterministic notation-resistant declaration-type and result-type representations. |
| FR-014 batch summaries | done | Batch text and JSON summaries include scanned, passed, warned, failed, unknown-bearing declaration counts, policy identifier, and schema version. |
| FR-015 stable JSON | done | Single-report and batch JSON are versioned, deterministic, schema-checked, and carry tool version, Lean version, schema version, transparency mode, policy identifier, policy digest, transparency-limited status, unknown status, and cycle status. CLI policy modifications are recorded in the reported identifier, and the digest identifies effective policy semantics independently of the label. |
| FR-016 differential mode | done | CLI `--diff <baseline.json> <current.json>` compares single-report or batch JSON artifacts by target and emits stable text/JSON for added, removed, policy-result-changed, finding-category-changed, and top-level-boundary-shape-changed declarations. |
| FR-017 failure clustering | done | CLI `--cluster <audit.json>` groups failing declarations from single-report or batch JSON artifacts by report-derived finding kind, category, source class, `type_name`, and module/lane metadata when present. Missing module/lane data remains `null`/`none`; no project-specific grouping heuristic is inferred. |
| FR-018 hidden-vs-explicit remediation signals | done | Cluster reports classify every failing declaration as `hidden`, `explicit_direct_prop`, `explicit_typeclass`, or `mixed`, inferred mechanically from public finding categories with unrecognized content conservatively hidden; unit tests pin the classification and golden tests pin the rendered output. |
| FR-019 priority and trend summaries | done | Cluster reports carry a deterministic `trend` block: per-signal failing-declaration counts, hidden and explicit-direct-prop failure families ordered by descending declaration count then type name, and per-lane counts when lane metadata is present; batch summaries and delta reports supply the counts and baseline deltas. Fields absent from artifacts stay `null`/`none` rather than inferred. |

## Classification Rules

| Requirement | Status | Notes |
| --- | --- | --- |
| mandatory public categories | done | All mandatory categories are modeled and executable tests cover `pure_data`, `direct_prop`, `proof_carrying_data`, `package_with_prop_fields`, `typeclass_assumption`, `alias`, and `unknown`. |
| primary plus secondary classification flags | done | Secondary flags are modeled and tested for proof-hypothesis binders, `Prop` quantifier binders, instance binders, and cycle truncation. |

## Policy Semantics

| Requirement | Status | Notes |
| --- | --- | --- |
| `pass` / `warn` / `fail` / `audit_error` | done | Implemented in `LeanAssumptions.Policy` and tested through strict, allowlisted, cycle, transparency-mismatch, and CLI exit-code cases. Machine-checked theorems additionally prove findings-preservation, audit-error dominance, transparency-mismatch unrecoverability, digest label-independence, and empty-findings-pass, kernel-replayed on every build. |
| strict-mode unknown handling | done | Strict policy fails unknown nodes and cycle truncation; unknowns may only be downgraded by explicit policy configuration. |

## Hardening Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| HR-001 minimal trusted core | done | The trusted core is limited to `Core` and `Policy`; trusted-core modules use no `axiom`, `constant`, `opaque`, `unsafe`, `extern`, `@[implemented_by]`, or `native_decide` (re-verify: `grep -nE 'axiom|opaque|unsafe|extern|implemented_by|native_decide' LeanAssumptions/Core*/** LeanAssumptions/Policy.lean`). No exceptions exist to document. Fixture-only suspicious constructs remain confined to `LeanAssumptionsTest/Fixtures`, and the policy engine additionally carries kernel-checked theorems. |
| HR-002 no silent fallback | done | Core, policy, command, CLI, and schema validators do not silently fall back from stricter modes; parse/import/policy errors are explicit failures. |
| HR-003 no network dependence | done | The runtime audit path is local-only. |
| HR-004 reproducible reports | done | Reports are reproducible by construction: deterministic ordering everywhere, generated fvar IDs erased, no timestamps, LF-pinned text validated by a gate, and every golden re-verified byte-for-byte at test-driver runtime on each `lake test`. Documented boundary: byte comparison across hosted platforms is an operational check that runs once CI executes on a public remote; the same-inputs-same-bytes contract itself is enforced locally. |
| HR-005 honest limitations | done | README, specs, tracker, and renderer/command/CLI output document that the tool audits declaration types only and does not replace proof-axiom validation, sandboxing, or statement-equivalence checking. |

## Performance Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| interactive single-declaration inspection | done | The interactive surface is the in-editor `#print` command family, which reuses the elaborator's live environment. CLI single-declaration medians are measured on every gate run against recorded references with regression detection; CLI latency is dominated by environment import, stated in the README. Real-project latency measurement continues in the mathlib-scale scan campaign. |
| repository-scale scan behavior | done | Text-mode scans stream: each declaration is inspected, rendered, and printed before the next is inspected, retaining only summary counters, with a unit test pinning byte-equality against the batch renderer. JSON output is a single versioned artifact rendered whole by design, stated in the CLI docs. |
| dedicated performance regression tracking | done | `python3 scripts/check_performance_baseline.py` runs each representative CLI case three times, checks the median against a recorded per-case reference times a regression factor (regression detection) plus an absolute ceiling, validates JSON output and scanned counts, and writes a machine-readable timing report that CI uploads as an artifact for history. Mathlib-scale benchmarks are planned with the conservatism-at-scale campaign. |

## Documentation Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| docstrings on public definitions and major theorems | done | Current public definitions and fixture declarations are documented, and `doc-gen4` API docs build locally. |
| source-file module docstrings | done | Current Lean source files have module docstrings. |
| command docs with examples | done | README, `docs/phase3-spec.md`, `docs/baseline-spec.md`, and command module docs include examples for the public command surface and CLI. |
| README problem/limits/tool comparisons/policy/CI sections | done | README covers installation, the problem, explicit non-goals, relation to `#print axioms`/`leanchecker`/`comparator`, policy files, and CI commands. |
| doc-gen4 API docs build | done | Configured in `docbuild/` and locally validated with `DOCGEN_SRC=file lake build LeanAssumptions:docs`. |

## Testing Doctrine

| Requirement | Status | Notes |
| --- | --- | --- |
| TD-001 test-first rule | done | Instituted and evidenced: every feature in the history landed with its tests in the same change, including the property-based soundness oracle and machine-checked policy theorems. The rule remains permanently binding; the pull-request template and CONTRIBUTING.md operationalize it. |
| TD-002 regression rule | done | Instituted and evidenced: every bug fix in the history, including all six 2026-07-11 audit fixes, landed with a permanent regression test and a changelog entry. The rule remains permanently binding. |
| TD-003 layered test suite | done | Core unit, policy unit, integration, command/CLI integration, renderer golden tests, fixture tests, and a smoke-level performance baseline validator run. |
| TD-004 coverage obligation | done | The coverage ledger is now completeness-checked: `LeanAssumptionsTest/Coverage.lean` emits the public-declaration inventory during `lake test`, and `scripts/check_coverage_ledger.py` fails on any public declaration missing from the ledger, any stale ledger name, any unmapped definition, and any test reference that is neither an existing repo path nor a lake/python command. `Baseline.renderUpdateText` is now executed by a direct unit test. Line-level tooling remains a documented Lean toolchain gap (`docs/api-gaps.md`); the charter's mandated fallback — a machine-validated ledger — is fully enforced. |
| TD-005 required fixture corpus | done | Every required corpus item has fixtures with classification-asserting tests: all binder kinds, direct/implicit/instance propositions, plain data, structures and nested packages, `Subtype`/`Sigma`/`PSigma`, aliases in `abbrev`/`def`/`@[reducible] def` forms across all three transparency modes, no-assumption theorems, cyclic structure graphs, fuel exhaustion, suspicious fixture-only constructs with declaration-kind assertions, the adversarial false-pass shapes from the 2026-07-11 audit, and the proof-validity-versus-statement-surface pair asserted end to end. |
| TD-006 golden output stability | done | Golden text, single-report JSON, batch text/JSON, delta text/JSON, cluster text/JSON, and baseline text snapshots cover the renderer/support-layer contract and are schema-validated where JSON is emitted. Every golden comparison additionally re-runs at test-driver runtime on every `lake test`, so build caching cannot skip comparisons after a golden-file edit. |

## Verification Gates

| Gate | Status | Notes |
| --- | --- | --- |
| `lake build` | done | Verified in WSL on May 2, 2026 against Lean 4.30.0-rc2. |
| `lake test` | done | Verified in WSL on May 2, 2026 against Lean 4.30.0-rc2 using the configured Lake test driver. |
| `lake lint` | done | Verified in WSL on May 2, 2026 against Lean 4.30.0-rc2. The lint driver runs `lake --wfail build LeanAssumptions LeanAssumptionsTest lean-assumptions-test lean-assumptions`. |
| `leanchecker --fresh` | done | `lake env leanchecker --fresh LeanAssumptions` passes in WSL on May 2, 2026 against Lean 4.30.0-rc2. |
| JSON schema validation tests | done | `python3 scripts/check_report_schema.py` validates single-report, batch, nested baseline batch, delta, and cluster golden JSON plus a freshly emitted CLI artifact using the `jsonschema` library (Draft 2020-12, full keyword enforcement); `python3 scripts/check_policy_schema.py` validates all policy fixtures against the published policy schema. Both pass locally. |
| golden output tests | done | `LeanAssumptionsTest/Golden/Phase3.lean`, `LeanAssumptionsTest/Golden/Delta.lean`, `LeanAssumptionsTest/Golden/Cluster.lean`, and `LeanAssumptionsTest/Golden/Baseline.lean` pass and cover text, single JSON, batch JSON, delta, cluster, and baseline snapshots. |
| coverage-ledger validation | done | `python scripts/check_coverage_ledger.py` validates the current Lean file ledger. Stronger line-level coverage remains tracked under TD-004. |
| performance baseline validation | done | `python scripts/check_performance_baseline.py` validates the current two-case CLI smoke baseline locally; the local Windows workspace requires WSL execution for Lake. |
| local release-readiness validation | done | `python scripts/check_release_readiness.py` validates local Lake/Reservoir metadata, schema/changelog consistency, governance files, and a JSON CLI artifact smoke test. `--release` remains blocked while partial/tracked requirements exist. |
| docs build | done | `cd docbuild && DOCGEN_SRC=file lake build LeanAssumptions:docs` passes locally on May 2, 2026 against Lean 4.30.0-rc2. |
| cross-platform CI | done | Configured as an Ubuntu/macOS GitHub Actions matrix with SHA-pinned actions, enforced by `python3 scripts/check_ci_workflow.py`. Native Windows hosted CI is an intentionally documented deviation (Working Rule 10) after hosted-runner failures; the supported Windows path is WSL2. Hosted execution begins with the first public push. |

## CI and Release Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| GitHub Actions with `leanprover/lean-action` | done | CI skeleton is present and uses `leanprover/lean-action` on `ubuntu-latest`. |
| explicit build/test/lint/leanchecker jobs | done | Build, test, lint, leanchecker, coverage-ledger validation, report schema validation, policy schema validation, line-ending validation, runnable-example validation, performance baseline validation, release-readiness validation, CI workflow validation, CLI smoke test, and doc-gen4 docs build jobs are configured. Jobs that run public CLI smoke checks build `lean-assumptions` and `LeanAssumptionsTest.Fixtures` first. The workflow disables `lean-action` auto gates and runs explicit Lake gates under Bash for cross-platform toolchain PATH consistency. Hosted CI execution of this revision is not yet validated. |
| `ubuntu-latest` | done | Configured in `.github/workflows/ci.yml`; hosted CI execution is not locally validated. |
| `macos-latest` and native Windows support | done | `macos-latest` runs the same gates as Ubuntu with `python3` invocations that exist on macOS runners. Native `windows-latest` remains an intentionally documented deviation with WSL2 as the supported Windows path; the CI-contract checker enforces its absence so it cannot half-return. |
| scheduled Lean RC compatibility job | done | `.github/workflows/compatibility.yml` runs weekly/manual build+lint+leanchecker over the current Lean `stable` and `beta` elan channels, so the forward signal cannot go stale; the CI-contract checker enforces the channel matrix. Full test/golden certification applies only to the pinned toolchain, stated in the workflow. Hosted scheduling begins with the first public push. |
| automated Lean upgrade workflow | done | `.github/workflows/update.yml` runs a commit-pinned `leanprover-community/lean-update` weekly/manually with `update_if_modified: lean-toolchain` and repository validators, SHA-pinned with least-privilege permissions and an explicit, announced fresh-artifact skip. Hosted scheduling begins with the first public push. |
| local Reservoir metadata readiness | done | `lakefile.lean` declares version, description, keywords, Apache-2.0 license metadata, and `reservoir := true`; `python scripts/check_release_readiness.py` validates these fields locally. |
| release artifact sanity check | done | `python scripts/check_release_readiness.py` runs a JSON CLI smoke test through the public executable path and validates the scanned/passed counts and schema version. |
| changelog and schema-version review | done | The release-readiness validator checks the Unreleased changelog section and schema-version consistency, and a tag-triggered release workflow re-runs every merge gate plus `check_release_readiness.py --release`, which refuses to release while any tracker row is partial or tracked. Human sign-off on publication remains a process rule recorded in `CONTRIBUTING.md` and the charter. |
| semantic releases / Reservoir publication / compatibility notes | done | Release discipline is in place: v-prefixed semantic tags gated by the release workflow, compatibility notes and the schema-evolution policy in `docs/compatibility-policy.md`, and Reservoir metadata validated locally. Reservoir publication itself is an operator action (public repository, pushed tag, two stars); the README's Current Status section carries the live publication state. |
