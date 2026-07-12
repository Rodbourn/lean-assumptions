# Changelog

## Unreleased

- Add `statement_repr_digest` to report schema v1: an FNV-1a 64 digest of the
  notation-resistant `raw_declaration_type_repr`, giving consumers a rung-0
  statement-identity certificate (byte-equal digests under the same
  `lean_version` certify byte-identical elaborated statements). The field is
  always emitted but schema-optional, so artifacts from earlier tool versions
  remain valid inputs to delta, cluster, and baseline modes. The
  accompanying `docs/statement-identity-spec.md` fixes the identity-claim
  ladder and states what the digest never certifies — equal digests across
  Lean versions carry no claim, and statement-meaning equivalence stays
  permanently out of scope.
- Make golden snapshots toolchain-portable: checked-in goldens and the example
  expectation store live `Lean.versionString` bytes as a `<LEAN_VERSION>`
  token, and all golden comparisons (compile-time, test-driver runtime, and
  the example checker) normalize exactly those bytes before comparing. Emitted
  artifacts still carry the real version. The scheduled compatibility workflow
  now runs the full `lake test` suite on the Lean `stable` and `beta` channels
  instead of skipping behavioral validation off the pinned toolchain, and the
  CI-contract checker enforces it.

## 0.2.1 - 2026-07-12

- Build the `LeanAssumptions` library explicitly in the performance-baseline and release-readiness CI jobs. The CLI imports the root `LeanAssumptions` module at runtime, but that module was outside the build closure of the two jobs' build targets, so any cold-cache run — including the v0.2.0 tag run — failed with a missing `LeanAssumptions.olean` before the checks could execute; warm caches from earlier full builds had masked the gap. The CI workflow validator now pins the strengthened build command so a regression to the old command fails locally.

## 0.2.0 - 2026-07-12

- Publish the project charter as `CHARTER.md`: the previously unpublished charter that README, CONTRIBUTING, and SECURITY referenced now ships in the repository, addressed to contributors.

- Publish the 2026-07-11 audit in full (`docs/audit-2026-07-11.md`): methodology honestly attributed as maintainer-directed multi-agent review, every finding with its minimal reproducer and fix commit, the gate-vacuousness postmortem, and what the audit did not establish. Ready-to-file issue drafts accompany it, and the README gains a maintenance-expectations section.
- Rename the command surface before any downstream adoption: `#assumptions` (hidden-surface default), `#assumptions strict`, and `#assumptions_json` replace the `#print assumptions` family, which extended core's `#print` syntax; the redundant `#print assumption_tree` spelling is dropped. The strict marker is a non-reserved keyword, so `strict` remains usable as an ordinary identifier downstream.
- Make the hidden-surface policy the in-editor default: bare commands flag only assumptions a reader cannot see in the statement as written (packaged proposition fields, proof-carrying data, unexpanded aliases, unknowns), while `strict` variants and the CLI's strict default preserve the certification posture. A `--preset strict|hidden` CLI flag selects the base policy.
- Add policy granularity for real theorem corpora: `direct_prop_policy` and `alias_policy` treatments, `permit_direct_prop_types` (match direct propositions by proposition head rather than binder name), and `permit_typeclass_types` (allow named classes while typeclass_policy stays warn/fail) in policy files and the policy engine. The canonical policy description bumps to v2, so all policy digests change.
- Add a `--transparency` CLI flag so alias-transparency modes are reachable without a policy file; the setting composes with `--policy` order-independently and is recorded in the policy identifier and digest. `--help` now describes every flag, the composition rules, and the exit codes. README quick-start commands use `lake exe`, which builds the executable on demand for downstream users. Regression fixtures pin that imax-spelled `Prop` sorts arrive normalized from the elaborator and classify as direct propositions.
- Update the pinned Lean toolchain from `v4.30.0-rc2` to `v4.31.0`, the latest stable release, resolving the automated update issue: the entire library including the certified core and its machine-checked theorems builds unchanged, all goldens are regenerated for the new version string, and the doc-gen4 build tracks the same toolchain. The package is now consumable from stable-toolchain projects.
- Raise the stack limit when elaborating the runnable example in `scripts/check_examples.py`: a hosted release-readiness job segfaulted (exit 139) on a command that passed in both build-test jobs of the same run, the signature of near-threshold stack exhaustion in interpreted metaprogram elaboration.

- Bootstrap repository skeleton for Phase 0 and Phase 1.
- Add certified-path report model, fixture corpus, and test layout.
- Track all deferred project requirements explicitly instead of leaving them implicit.
- Add recursive structure/class expansion, proof-carrying data detection, cycle-safe unknown reporting, and strict policy evaluation.
- Add deterministic text, single-report JSON, and batch JSON renderers with golden tests and local schema validators.
- Add `#print assumptions`, `#print assumption_tree`, and `#print assumption_json`.
- Add the `lean-assumptions` CLI with declaration inspection, declaration lists, module scans, policy-file parsing, text/JSON output, and CI-oriented exit codes.
- Add versioned report, batch-report, and policy JSON schemas.
- Add a nested `doc-gen4` API documentation build under `docbuild/`.
- Add a cross-platform CI matrix for Ubuntu, macOS, and Windows plus a local CI workflow validator.
- Add a scheduled Lean release-candidate compatibility workflow.
- Add an automated Lean upgrade workflow using `leanprover-community/lean-update`.
- Add a Phase 4 smoke-level performance baseline and CI validator.
- Add local release-hardening checks for Lake/Reservoir metadata, schema/changelog consistency, governance files, and CLI artifact sanity.
- Implement certified-path alias transparency semantics for `none`, `reducible`, and `recursive_normalization` modes, with strict policy failures for unsupported aliases.
- Add repository-agnostic delta reporting for prior/current JSON audit artifacts, with CLI `--diff`, stable text/JSON output, schema validation, and golden tests.
- Add repository-agnostic failure clustering for JSON audit artifacts, with CLI `--cluster`, stable text/JSON output, schema validation, and golden tests.
- Add baseline mode over v1 batch JSON artifacts, with CLI `--baseline`, `--accept`, and `--update-baseline` support for freezing existing finding debt.
- Add a runnable hidden-package example with checked output for `#print axioms`, `#print assumptions`, `#print assumption_tree`, and `#print assumption_json`.
- Pin repository text files to LF line endings and validate them for cross-platform golden tests.
- Harden GitHub Actions Lake steps to use Bash consistently after Lean toolchain setup.
- Temporarily remove hosted Windows from the CI matrix while retaining identical Ubuntu and macOS gates.
- Build the CLI executable and test fixture module before CI performance and release-readiness smoke checks.
- Reduce CLI integration-test latency by reusing an imported Lean environment and suppressing repeated report output.
- Distinguish proof-hypothesis binders from binders that quantify over `Prop` by adding the `binder_quantifies_over_prop` secondary flag to report schema v1.
- Escape all U+0000 through U+001F control characters in JSON string output across report, delta, and cluster renderers.
- Document confirmed certified-path soundness gaps in the README and downgrade the affected requirement-tracker rows ahead of their fixes.
- Classify unrecognized binder-type head shapes as `unknown` instead of `pure_data`: classification is now by positive recognition of sorts, bound type variables, structures, non-structure inductives (scanned constructor by constructor), function result types, and `Quot` payloads, with structural beta/zeta/projection reduction applied under every transparency mode. Packages whose fields remain unexpanded `alias` nodes now classify `unknown` instead of `pure_data`. Adds adversarial regression fixtures from the 2026-07-11 audit.
- Detect every unfoldable definition head (`abbrev`, `def`, `@[reducible] def`) as an `alias` node under `none` transparency instead of only `abbrev` hints. Proof binders whose proposition is spelled through an alias now report `direct_prop` rather than `alias`, because proposition evidence is transparency-independent.
- Audit the declaration surface itself: binder peeling now normalizes round by round under the report transparency mode, so statements hidden behind aliases are either unfolded and peeled (`reducible`, `recursive_normalization`) or reported as an explicit blocked `result` surface that fails strict policy (`none`). Report JSON schema v1 gains a `result_surface` field (node or `null`).
- Key cycle detection on normalized type instances instead of structure head names, so nested same-head generics such as `Nat × Nat × Nat` no longer fail strict policy as truncated cycles while genuinely cyclic package graphs still truncate explicitly.
- Pin every reduction site to the report transparency mode and make the three modes operationally distinct: `reducible` now reduces at reducible transparency (plain `def` heads stay folded and report `alias`), `recursive_normalization` normalizes at default transparency to a fixed point, and the proof-carrying wrapper checks can no longer unfold more than the mode permits. Report schema v1 gains a `transparency_limited` field that is `true` whenever unexpanded alias heads remain in the report.
- Validate at mathlib scale: 1,331 declarations scanned across three pinned mathlib modules with zero crashes, byte-identical deterministic re-runs, correct exit codes, 1.4% conservatively-unknown declarations (all recursor-headed or stuck-application types — the designed failure direction), and FR-018/FR-019 trend analytics exercised on real artifacts; procedure and results in `docs/mathlib-scale-validation.md`.
- Stream text-mode module scans: each declaration is inspected, rendered, and printed before the next is inspected, with byte-equality against the batch renderer pinned by a unit test; JSON output remains a single versioned artifact by design.
- Resolve every remaining requirement-tracker row with evidence or an explicitly documented operational boundary, and correct the charter's support-layer enumeration to include `LeanAssumptions/Baseline` and `LeanAssumptions/JsonUtil`.
- Implement FR-018 and FR-019: cluster reports now carry a deterministic `trend` block with hidden/explicit-direct-prop/explicit-typeclass/mixed remediation-signal counts per failing declaration (unrecognized categories conservatively hidden), report-derived failure families ordered by declaration count, and per-lane counts when lane metadata is present. Cluster schema v1 gains the `trend` object.
- Prove machine-checked properties of the certified policy engine, replayed by the kernel on every build and by `leanchecker`: the policy digest is independent of the identifier label; policy evaluation never removes findings (`any`-predicate preservation through `evaluateOwnNode` and `evaluateWork`); any audit-error finding forces the overall `audit_error` result; a transparency mismatch between policy and report is unrecoverable no matter what the report contains; and empty findings are exactly a `pass`. `evaluate` is refactored into named seed/work/findings helpers with identical semantics to make the proofs readable.
- Add a property-based soundness oracle: the test suite now GENERATES a corpus sweeping nine proposition-embedding sites (direct, structure field, nested package, inductive constructor field, function codomain, `Subtype`, `PSigma`, tuple, list element) across explicit/implicit/strict-implicit binder kinds, plus data-only mirror controls, and asserts that every positive fails strict policy and every negative passes. A false pass is reported as a certified-path correctness incident. This is the mechanical oracle that would have caught every false-pass class the 2026-07-11 audit found.
- Add governance and adoption documentation: a documented backward-compatibility policy for command names, CLI flags, and schemas (`docs/compatibility-policy.md`, completing FR-009), a security policy with a private reporting channel and response commitments, `CONTRIBUTING.md`, a pull-request template enforcing the testing doctrine checklist, a `NOTICE` file with the copyright holder, and README installation instructions.
- Add a tag-triggered release workflow that re-runs every merge gate plus `check_release_readiness.py --release` on v-prefixed tags, so a release tag cannot green without the full release discipline; the CI-contract checker enforces its presence and shape.
- Turn the performance gate into a regression detector: each representative CLI case now runs three times, the median is checked against a recorded per-case reference times a regression factor as well as the absolute ceiling, and a machine-readable timing report is written and uploaded as a CI artifact for history (performance baseline schema v2).
- Rework the compatibility workflow into a forward signal: a weekly matrix over the current Lean `stable` and `beta` elan channels runs build, lint, and leanchecker, replacing the previous job that re-tested the repository's own pinned toolchain and could never produce new information. Golden-dependent tests remain scoped to the pinned toolchain, and the workflow says so.
- Harden GitHub Actions workflows: every action is pinned by commit SHA (including `leanprover-community/lean-update`, previously a mutable `@main` reference holding write permissions), workflows declare least-privilege `permissions:` blocks and concurrency groups, and every checker script runs under `python3` (bare `python` is absent on macOS runners). `scripts/check_ci_workflow.py` enforces the pinned-SHA, permissions, concurrency, and python3 contract.
- Re-run every golden comparison at test-driver runtime: elaboration-time `run_cmd` comparisons are skipped by build caching when only a golden file changed, so `lake test` could previously pass against a corrupted snapshot. The test executable now re-verifies all text, JSON, batch, delta, cluster, and baseline goldens on every run and fails with named mismatches.
- Carry the running Lean version plus the baseline and current artifacts' recorded Lean versions in baseline comparison and update text output, completing the charter's required artifact metadata for baseline mode.
- `--help` now prints usage to stdout and exits 0 instead of exiting 2 through the error path, and the usage text documents every accepted flag including `--warn-unknowns` and `--help`; an integration test guards against future usage drift.
- Reject malformed audit-artifact inputs explicitly in the support layers: cluster mode now fails with a parse error on unrecognized `policy_result` or finding-severity spellings instead of silently treating them as non-failing, and both cluster and delta modes reject artifacts whose `schema_version` is not `1`.
- Escape names, policy identifiers, and string literals in human-readable text reports the same way JSON strings are escaped, so a hostile declaration or binder name containing newlines can no longer forge report lines such as a fake `policy_result:` entry.
- Strengthen the layered test suite: unit tests for the policy-file parser (every error branch and both pattern spellings), the policy traversal-budget audit-error branch, and core expansion-fuel exhaustion; a golden snapshot for batch text output; CLI integration tests for unknown/incomplete options, bad formats, missing modules or work, unknown declarations, malformed policy files, and malformed or missing diff/cluster artifacts; and classification assertions for the proof-validity-versus-statement-surface fixture pair and suspicious fixture-only declaration kinds.
- Validate JSON schemas with the `jsonschema` library (Draft 2020-12) instead of hand-rolled partial validators, so `pattern`, `oneOf`, and every other schema keyword are actually enforced; the report-schema gate additionally validates a freshly emitted CLI artifact on every run, and any skip of that fresh check must be explicit and is announced in the output. Policy fixtures are now discovered by glob and validated against the published policy schema itself.
- Make the coverage-ledger gate non-vacuous: building the test suite now emits a public-declaration inventory (`LeanAssumptionsTest/Coverage.lean`), and `scripts/check_coverage_ledger.py` diffs the ledger against it — unlisted public declarations, stale ledger names, unmapped definitions, and dangling test references all fail the gate. The ledger now maps all 103 hand-written public declarations to their covering tests, `Baseline.renderUpdateText` gained a direct unit test, and scratch files in untracked local directories are excluded from ledger scope.
- Record CLI policy modifications truthfully in public artifacts: `--allow-*` and `--warn-unknowns` flags now compose on top of the base policy regardless of argument order and extend the reported `policy_identifier` with sorted modifier segments, duplicate `--policy` options are rejected explicitly instead of last-wins, and report/batch schema v1 gain a `policy_digest` field (FNV-1a 64 over a canonical, label-independent policy description).
