# Compatibility and Backward-Compatibility Policy

This page is the documented compatibility policy that the charter's FR-009 and
"Public API Policy" sections require. It governs every public surface of
`lean-assumptions`.

## Public surfaces under compatibility discipline

The following are public APIs. Changing any of them is a compatibility event:

| Surface | Contract |
| --- | --- |
| Command names (`#assumptions`, `#assumptions strict`, `#assumptions_json`) | Stable from v0.2.0. The pre-adoption `#print assumptions` family was renamed on 2026-07-12, before any downstream use, to avoid extending core's `#print` syntax; names may change hereafter only for strong community reasons, with the old spelling kept as a deprecated alias for at least one minor release. |
| CLI flags and exit codes | Stable. New flags may be added freely; existing flags may not change meaning or arity. Removing or renaming a flag requires a deprecation period of one minor release during which the old flag still works and warns. Exit-code semantics (`0` pass/warn, `1` fail/audit error, `2` usage/parse) may not change within a major version. |
| Report JSON (`schema/report-v1.schema.json`, `schema/batch-report-v1.schema.json`) | Versioned. See schema evolution rules below. |
| Delta and cluster JSON (`schema/delta-report-v1.schema.json`, `schema/cluster-report-v1.schema.json`) | Versioned. Same rules. |
| Policy-file format (`schema/policy-v1.schema.json`) | Versioned. Same rules, plus: unknown keys are rejected rather than ignored so policy typos cannot silently weaken an audit. |
| Human-readable text output | May evolve more freely, but only with changelog entries and reviewed golden updates; JSON must stay stable while text changes. |

## Schema evolution rules

- Before the first public release, schemas may change in place as long as the
  changelog records each change; schema `v1` has never been published.
- After the first public release:
  - **Additive** changes (new optional fields, or new required fields that
    consumers validating with `additionalProperties: false` would reject)
    require a minor schema revision documented in `schema/README.md` and the
    changelog, and golden regeneration in the same change.
  - **Breaking** changes (removing or renaming fields, changing field types or
    enum spellings, changing semantics of an existing field) require a new
    schema version (`report-v2`), a new `schema_version` value emitted by the
    renderers, and support-layer readers that reject versions they do not
    understand rather than guessing.
- Every emitted artifact names its `schema_version`; delta, cluster, and
  baseline modes reject artifact versions they do not support.
- Policy semantics may never change silently in a patch release (charter
  governance rule). A change to what a policy accepts or rejects is at least a
  minor release with a changelog entry.

## Toolchain support window

Per the charter's compatibility policy, the project aims to support the latest
Lean stable release and the current release candidate.

Current state: the repository pins `leanprover/lean4:v4.31.0`, the latest
stable Lean release, in `lean-toolchain`. Full behavioral validation (tests
and golden snapshots, which embed the toolchain's version string) applies only
to that pinned toolchain. A weekly compatibility workflow
builds, lints, and kernel-replays the package on the current `stable` and
`beta` elan channels so forward incompatibilities surface without manual
re-pinning; a scheduled update workflow proposes toolchain bumps. If a Lean
API change forces a semantic change in reports, the schema or report-model
version must be bumped in the same change.

## What compatibility does not promise

- Byte-identical text reports across tool versions (text may evolve with
  review; JSON is the stable machine surface).
- Identical classification results across transparency modes (mode is part of
  the report contract and every artifact names its mode).
- Classification stability across Lean versions when Lean's own elaboration
  changes; artifacts name the Lean version for exactly this reason.
