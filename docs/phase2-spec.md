# Phase 2 Behavioral Spec

This document records the executable Phase 2 behavior now implemented in the
certified path. It is not a claim that the full project is complete.

Implemented core classification behavior:

- structure and class applications are expanded recursively for inspected binders and fields
- recursive expansion is fuel-bounded and cycle-safe
- cycles are reported as `unknown` nodes with the `cycleTruncated` secondary flag
- report-level `unknownsOccurred` and `cyclesTruncated` flags are set when any inspected path is unknown or cycle-truncated
- field ordering follows Lean structure field order and is deterministic
- non-instance package binders with proposition-bearing descendants are classified as `package_with_prop_fields`
- instance-implicit class binders keep `typeclass_assumption` as their primary category while exposing inspected children
- `Subtype`, `Sigma`, and `PSigma` proof-carrying payloads are classified as `proof_carrying_data` when the proof component is visible under the current rules
- proposition fields and proof witnesses inside approved packages are still visible in the normalized tree
- alias transparency is explicit:
  - `none` reports reducible alias heads as `alias` nodes instead of silently expanding them
  - `reducible` expands abbreviation heads enough to classify the exposed package
  - `recursive_normalization` applies the project normalizer repeatedly at each inspected node
- raw declaration types remain visible, so reports can show an alias-bearing statement even when the inspected node type is normalized under a non-`none` transparency mode

Implemented policy behavior:

- `LeanAssumptions.Policy.evaluate` deterministically evaluates an `AssumptionReport`
- `strictPolicy` fails unapproved direct proposition binders
- `strictPolicy` fails unapproved packages with proposition-bearing fields
- `strictPolicy` fails unapproved proof-carrying data wrappers
- `strictPolicy` fails unapproved typeclass assumptions
- unknown nodes fail unless the policy explicitly permits or warns on unknowns
- cycle truncation is always a policy failure in the current strict engine
- transparency-mode mismatch is an `audit_error`
- unsupported alias nodes fail under strict policy unless alias treatment is explicitly relaxed
- exact-name allowlists are implemented for direct proposition binders and packaged/proof-carrying type heads
- prefix-name patterns are explicit and available for future policy-file parsing

Phase 2 boundary:

- policy-file parsing, rendering, JSON output, command syntax, and CLI are Phase 3 support-layer deliverables, not Phase 2 certified-path deliverables
- Phase 3 owns renderer, schema, golden, command, and CLI work
- performance benchmarks remain scaffolded for later phases

The corresponding tests currently live in:

- `LeanAssumptionsTest/Unit/Core/Phase2.lean`
- `LeanAssumptionsTest/Unit/Policy/Phase2.lean`
