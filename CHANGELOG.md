# Changelog

## Unreleased

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
- Add a runnable hidden-package example with checked output for `#print axioms`, `#print assumptions`, `#print assumption_tree`, and `#print assumption_json`.
- Pin repository text files to LF line endings and validate them for cross-platform golden tests.
- Harden GitHub Actions Lake steps to use Bash consistently after Lean toolchain setup.
- Temporarily remove hosted Windows from the CI matrix while retaining identical Ubuntu and macOS gates.
