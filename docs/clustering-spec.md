# Failure Clustering Spec

This document records the implemented repository-agnostic failure clustering
behavior required by FR-017. It is support-layer functionality: it consumes JSON
audit artifacts already emitted by `lean-assumptions`; it does not re-run Lean
elaboration, change trusted-core classification, or change policy semantics.

Cluster input requirements:

- input is one JSON artifact emitted by `lean-assumptions`
- the input may be a single-report artifact or a batch artifact containing
  `reports`
- malformed or unsupported artifacts are audit-input errors, not successful
  clustering runs
- duplicate declaration targets are rejected because they would make cluster
  membership ambiguous

Failure selection requirements:

- declarations with `policy_result` equal to `fail` or `audit_error` are
  considered failing declarations
- findings with `severity` equal to `failure` or `audit_error` are considered
  failing findings
- warning findings are not clustered as failures
- if a declaration is failing but carries no failing finding, clustering emits a
  conservative `missing_failure_finding` group with `source_class` set to
  `unknown`

Signature requirements:

- each cluster signature uses only public report fields
- signatures include finding kind, finding category, source class, `type_name`,
  module metadata, and lane metadata
- source class is derived mechanically from the finding category:
  `direct_prop`, `package`, `proof_carrying_data`, `typeclass`, `alias`,
  `unknown`, or `other`
- module and lane are `null` when absent from the input artifact; no module or
  lane is inferred from project-specific target naming conventions

Ordering requirements:

- declarations inside each cluster are sorted by target name
- clusters are sorted by descending declaration count, then by signature fields
- output is byte-stable for the same input artifact

Output requirements:

- stable human-readable text output
- versioned deterministic JSON described by
  `schema/cluster-report-v1.schema.json`
- tool version and cluster schema version
- source artifact schema version, Lean version, policy identifier, transparency
  mode, and declaration counts when present
- summary counts for declarations scanned, failing declarations, failure
  findings clustered, and clusters
- explicit limitations stating that clustering compares rendered audit artifacts
  only and does not validate proof axioms, sandbox execution, prove
  statement-equivalence, infer project-specific cleanup lanes, or suggest
  remediation

Current boundary:

- hidden-vs-explicit remediation signals are tracked under FR-018
- priority-oriented and trend artifacts are tracked under FR-019
- no project-specific lane names, theorem families, policy names, or cleanup
  heuristics are allowed

Executable coverage:

- `LeanAssumptions.Cluster` implements typed artifact parsing, grouping, and
  stable text/JSON rendering
- `LeanAssumptionsTest/Golden/Cluster.lean` checks summary counts and exact
  golden text/JSON output
- `LeanAssumptionsTest/Integration/Cli.lean` checks CLI `--cluster` text/JSON
  exit behavior and mixed-mode rejection
- `scripts/check_report_schema.py` validates `cluster-report-v1.schema.json`
  against committed cluster golden JSON
