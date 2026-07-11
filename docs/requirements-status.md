# Requirement Status

This tracker exists so deferred project requirements stay explicit.

Status labels:

- `done`: implemented and validated for the currently scoped phase
- `partial`: scaffolded or modeled, but not fully implemented or not fully validated
- `tracked`: explicitly deferred to a later phase

## Phases

- Phase 0 deliverables: `done`; full project gate completion: `partial`
- Phase 1 deliverables: `done` and locally verified; full project gate completion: `partial`
- Phase 2 deliverables: `done` for the certified core/policy scope; full project gate completion: `partial`
- Phase 3 deliverables: `done` and locally verified; full project completion: `partial`
- Phase 4: `partial`

The project is not finished while any requirement or verification gate below is
`partial` or `tracked`.

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
| FR-009 human-facing commands | partial | `#print assumptions`, `#print assumption_tree`, and `#print assumption_json` are implemented and exercised by integration tests. The backward-compatibility policy for command names that FR-009 requires is not yet documented anywhere. |
| FR-010 CLI | done | The `lean-assumptions` executable supports one declaration, declaration lists, module scans, text/JSON output, and nonzero exit codes for policy or audit failure. |
| FR-011 policy files | done | The CLI accepts versioned JSON policy files with exact/prefix allowlists, typeclass treatment, unknown treatment, and transparency mode; schema and fixture validation are present. |
| FR-012 conservative failure mode | done | Classification is by positive head recognition: unrecognized binder-type head shapes emit `unknown` and fail strict policy, unfoldable definition heads report `alias` under `none` transparency, `let` wrappers reduce structurally, non-structure inductives are scanned constructor by constructor, and function types classify through their result type. Declaration surfaces that stop at an alias-headed or unpeelable remainder report an explicit `result` surface node that fails strict policy. |
| FR-013 raw theorem-surface visibility | done | Text, JSON, command, and CLI outputs include deterministic notation-resistant declaration-type and result-type representations. |
| FR-014 batch summaries | done | Batch text and JSON summaries include scanned, passed, warned, failed, unknown-bearing declaration counts, policy identifier, and schema version. |
| FR-015 stable JSON | done | Single-report and batch JSON are versioned, deterministic, schema-checked, and carry tool version, Lean version, schema version, transparency mode, policy identifier, policy digest, transparency-limited status, unknown status, and cycle status. CLI policy modifications are recorded in the reported identifier, and the digest identifies effective policy semantics independently of the label. |
| FR-016 differential mode | done | CLI `--diff <baseline.json> <current.json>` compares single-report or batch JSON artifacts by target and emits stable text/JSON for added, removed, policy-result-changed, finding-category-changed, and top-level-boundary-shape-changed declarations. |
| FR-017 failure clustering | done | CLI `--cluster <audit.json>` groups failing declarations from single-report or batch JSON artifacts by report-derived finding kind, category, source class, `type_name`, and module/lane metadata when present. Missing module/lane data remains `null`/`none`; no project-specific grouping heuristic is inferred. |
| FR-018 hidden-vs-explicit remediation signals | tracked | Hidden package/data-wrapper versus explicit direct-proposition/typeclass failure classification is not implemented yet. |
| FR-019 priority and trend summaries | tracked | Priority-oriented cleanup summaries and compact CI trend artifacts are not implemented yet. Existing batch summaries, delta reports, and failure clusters do not provide hidden-vs-explicit signals, per-lane counts, or dashboard trend artifacts. |

## Classification Rules

| Requirement | Status | Notes |
| --- | --- | --- |
| mandatory public categories | done | All mandatory categories are modeled and executable tests cover `pure_data`, `direct_prop`, `proof_carrying_data`, `package_with_prop_fields`, `typeclass_assumption`, `alias`, and `unknown`. |
| primary plus secondary classification flags | done | Secondary flags are modeled and tested for proof-hypothesis binders, `Prop` quantifier binders, instance binders, and cycle truncation. |

## Policy Semantics

| Requirement | Status | Notes |
| --- | --- | --- |
| `pass` / `warn` / `fail` / `audit_error` | done | Implemented in `LeanAssumptions.Policy` and tested through strict, allowlisted, cycle, transparency-mismatch, and CLI exit-code cases. |
| strict-mode unknown handling | done | Strict policy fails unknown nodes and cycle truncation; unknowns may only be downgraded by explicit policy configuration. |

## Hardening Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| HR-001 minimal trusted core | partial | The certified path is limited to `Core` and `Policy`; implemented certified modules use no `axiom`, `constant`, `opaque`, `unsafe`, `extern`, `@[implemented_by]`, or `native_decide`. Fixture-only suspicious constructs remain confined to `LeanAssumptionsTest/Fixtures`. |
| HR-002 no silent fallback | done | Core, policy, command, CLI, and schema validators do not silently fall back from stricter modes; parse/import/policy errors are explicit failures. |
| HR-003 no network dependence | done | The runtime audit path is local-only. |
| HR-004 reproducible reports | partial | Internal report order and renderer output are deterministic and erase generated local fvar IDs. Repository text files are pinned to LF line endings and checked locally; cross-platform byte stability is still awaiting hosted CI validation. |
| HR-005 honest limitations | done | README, specs, tracker, and renderer/command/CLI output document that the tool audits declaration types only and does not replace proof-axiom validation, sandboxing, or statement-equivalence checking. |

## Performance Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| interactive single-declaration inspection | partial | A Phase 4 smoke baseline validates a representative single-declaration CLI audit within a broad threshold. This is not yet a detailed latency benchmark across real projects. |
| repository-scale scan behavior | partial | Module scanning is implemented, but incremental/chunked large-scan behavior remains tracked beyond the current baseline. |
| dedicated performance regression tracking | done | `python3 scripts/check_performance_baseline.py` runs each representative CLI case three times, checks the median against a recorded per-case reference times a regression factor (regression detection) plus an absolute ceiling, validates JSON output and scanned counts, and writes a machine-readable timing report that CI uploads as an artifact for history. Mathlib-scale benchmarks are planned with the conservatism-at-scale campaign. |

## Documentation Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| docstrings on public definitions and major theorems | done | Current public definitions and fixture declarations are documented, and `doc-gen4` API docs build locally. |
| source-file module docstrings | done | Current Lean source files have module docstrings. |
| command docs with examples | done | README, `docs/phase3-spec.md`, `docs/baseline-spec.md`, and command module docs include examples for the public command surface and CLI. |
| README problem/limits/tool comparisons/policy/CI sections | done | README covers the problem, explicit non-goals, relation to `#print axioms`/`leanchecker`/`comparator`, policy files, and CI commands. |
| doc-gen4 API docs build | done | Configured in `docbuild/` and locally validated with `DOCGEN_SRC=file lake build LeanAssumptions:docs`. |

## Testing Doctrine

| Requirement | Status | Notes |
| --- | --- | --- |
| TD-001 test-first rule | partial | Phase 1, Phase 2, implemented Phase 3, FR-016 delta, FR-017 cluster, and baseline-mode behaviors landed with tests in the same change set. The rule remains active for later features and bug fixes. |
| TD-002 regression rule | partial | Existing `fix(core)` and `fix(render)` changes landed with regression tests in the same change. The rule remains in force for all future fixes, including the audit-confirmed soundness gaps. |
| TD-003 layered test suite | done | Core unit, policy unit, integration, command/CLI integration, renderer golden tests, fixture tests, and a smoke-level performance baseline validator run. |
| TD-004 coverage obligation | partial | The coverage ledger is now completeness-checked: `LeanAssumptionsTest/Coverage.lean` emits the public-declaration inventory during `lake test`, and `scripts/check_coverage_ledger.py` fails on any public declaration missing from the ledger, any stale ledger name, any unmapped definition, and any test reference that is neither an existing repo path nor a lake/python command. `Baseline.renderUpdateText` is now executed by a direct unit test. Line-level enforcement remains tracked pending Lean coverage tooling. |
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
| cross-platform CI | partial | Configured as an Ubuntu/macOS GitHub Actions matrix and checked by `python scripts/check_ci_workflow.py`. Native Windows hosted CI is intentionally deferred; Windows users should run the package under WSL2 for now. |

## CI and Release Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| GitHub Actions with `leanprover/lean-action` | done | CI skeleton is present and uses `leanprover/lean-action` on `ubuntu-latest`. |
| explicit build/test/lint/leanchecker jobs | done | Build, test, lint, leanchecker, coverage-ledger validation, report schema validation, policy schema validation, line-ending validation, runnable-example validation, performance baseline validation, release-readiness validation, CI workflow validation, CLI smoke test, and doc-gen4 docs build jobs are configured. Jobs that run public CLI smoke checks build `lean-assumptions` and `LeanAssumptionsTest.Fixtures` first. The workflow disables `lean-action` auto gates and runs explicit Lake gates under Bash for cross-platform toolchain PATH consistency. Hosted CI execution of this revision is not yet validated. |
| `ubuntu-latest` | done | Configured in `.github/workflows/ci.yml`; hosted CI execution is not locally validated. |
| `macos-latest` and native Windows support | partial | `macos-latest` is configured in the main matrix and runs the same gates as Ubuntu. Native `windows-latest` CI is intentionally unsupported for now after hosted native-Windows runner failures; the supported Windows path is WSL2. |
| scheduled Lean RC compatibility job | partial | `.github/workflows/compatibility.yml` runs weekly/manual build+lint+leanchecker over the current Lean `stable` and `beta` elan channels, so the forward signal cannot go stale; `python3 scripts/check_ci_workflow.py` enforces the channel matrix. Full test/golden certification applies only to the pinned toolchain. Hosted scheduled execution is not locally observable. |
| automated Lean upgrade workflow | partial | `.github/workflows/update.yml` is configured for weekly/manual runs of a commit-pinned `leanprover-community/lean-update` with `update_if_modified: lean-toolchain` and repository-specific validators; workflows are SHA-pinned with least-privilege permissions. Hosted execution is not locally observable. |
| local Reservoir metadata readiness | done | `lakefile.lean` declares version, description, keywords, Apache-2.0 license metadata, and `reservoir := true`; `python scripts/check_release_readiness.py` validates these fields locally. |
| release artifact sanity check | done | `python scripts/check_release_readiness.py` runs a JSON CLI smoke test through the public executable path and validates the scanned/passed counts and schema version. |
| changelog and schema-version review | partial | The local release-readiness validator checks the Unreleased changelog section and schema-version consistency, and a tag-triggered release workflow re-runs every merge gate plus `check_release_readiness.py --release`, which refuses to release while any requirement is partial or tracked. Human release review and any schema-version bump decision remain required before a real tag. |
| semantic releases / Reservoir publication / compatibility notes | partial | A `0.1.0` public prerelease tag exists. No final release artifact has been published, no Reservoir publication has occurred, and release compatibility notes are not finalized. |
