# Delta Reporting Spec

This document records the implemented repository-agnostic delta reporting
behavior required by FR-016. It is support-layer functionality: it compares JSON
audit artifacts already emitted by `lean-assumptions`; it does not re-run Lean
elaboration, change certified classification, or change policy semantics.

Delta input requirements:

- inputs are two JSON artifacts emitted by `lean-assumptions`
- each input may be a single-report artifact or a batch artifact containing
  `reports`
- declarations are matched by stable `target` name
- malformed or unsupported artifacts are audit-input errors, not successful
  comparisons

Delta comparison requirements:

- report declarations present only in the current artifact as added
- report declarations present only in the baseline artifact as removed
- report declarations whose `policy_result` changed
- report declarations whose sorted policy-finding category set changed
- report declarations whose top-level boundary shape changed
- preserve deterministic target ordering

Top-level boundary shape is the ordered list of top-level assumption-tree
nodes, using each node's name, binder kind, primary category, and rendered binder
type. Child expansion differences remain visible through the ordinary report
artifacts and future summary work; this tranche only compares the top-level
boundary required by FR-016.

Delta output requirements:

- stable human-readable text output
- versioned deterministic JSON output described by
  `schema/delta-report-v1.schema.json`
- tool version and delta schema version
- baseline/current schema version, Lean version, policy identifier,
  transparency mode, and declaration counts when present
- summary counts for added, removed, changed, result-changed,
  finding-category-changed, and boundary-shape-changed declarations
- explicit limitations stating that delta mode compares rendered audit artifacts
  only and does not validate proof axioms, sandbox execution, prove
  statement-equivalence, or suggest remediation

Current boundary:

- failure clustering by root-cause signature is tracked under FR-017
- hidden-vs-explicit remediation signals are tracked under FR-018
- priority-oriented and trend artifacts are tracked under FR-019
- no project-specific lane names, theorem families, policy names, or cleanup
  heuristics are allowed

Executable coverage:

- `LeanAssumptions.Delta` implements typed artifact parsing, comparison, and
  stable text/JSON rendering
- `LeanAssumptionsTest/Golden/Delta.lean` checks summary counts and exact golden
  text/JSON output
- `LeanAssumptionsTest/Integration/Cli.lean` checks CLI `--diff` text/JSON exit
  behavior and mixed-mode rejection
- `scripts/check_report_schema.py` validates `delta-report-v1.schema.json`
  against committed delta golden JSON
