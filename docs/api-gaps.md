# Lean API and Tooling Gaps

## Coverage Instrumentation

The current Lean 4.30.0-rc2 toolchain does not provide a repository-grade,
stable, built-in line coverage workflow suitable for enforcing the project's
coverage obligations directly in CI.

Tightened implementation boundary for current phases:

- maintain a machine-readable coverage ledger
- validate that implemented Lean source files and public definitions are mapped
  to tests
- keep the certified path small until stronger coverage tooling is available

No Phase 0/1/2 certified-path feature was omitted because of a known Lean API
limitation in declaration lookup, binder peeling, proposition detection,
structure/class expansion, cycle detection, proof-carrying wrapper detection, or
strict policy evaluation.

## API Documentation Build

The Phase 3 `doc-gen4` build path is configured in `docbuild/` and validated
with:

```text
DOCGEN_SRC=file lake build LeanAssumptions:docs
```

`DOCGEN_SRC=file` is required in this workspace because the default GitHub
source-link mode requires a git remote.
