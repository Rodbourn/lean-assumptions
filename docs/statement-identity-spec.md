# Statement-Identity Specification

This document defines exactly which statement-identity claims
`lean-assumptions` makes, the mechanical basis for each claim, and the claims
it will never make. It bounds the `statement_repr_digest` field of report
schema v1.

Vocabulary is fixed project-wide: this feature is an **identity certificate**.
The words "equivalence" and "same theorem" are never correct descriptions of
it. The charter is explicit that this tool "is not a sandbox, not an external
checker, and not a theorem-statement equivalence checker" and "must say so
repeatedly and plainly" (`CHARTER.md`, Threat Model); replacing `comparator`
is listed as out of scope. Challenge-versus-solution statement comparison is
`comparator`'s problem and remains so.

## The claim ladder

Each rung is strictly weaker than statement-meaning equivalence. Only rung 0
is implemented; the table records the project's permanent position on every
rung so future work cannot drift upward silently.

| Rung | Claim | Soundness basis | Status |
| --- | --- | --- | --- |
| 0 | Byte-equal `statement_repr_digest` (equivalently, byte-equal `raw_declaration_type_repr`) **and** equal `lean_version` ⇒ the two artifacts audited byte-identical elaborated declaration types, including binder display names | The representation is a deterministic constructor-spine encoding of the elaborated type with de Bruijn bound occurrences; byte equality of the encoding is stricter than alpha-equivalence | Implemented: `statement_repr_digest` in report v1 |
| 1 | Equal normal forms under a *stated* transparency mode and fuel ⇒ the statements are definitionally reachable from each other under that mode | Sound only if the mode and fuel are part of the claim itself | Not implemented; requires its own spec before any code |
| 2 | `Meta.isDefEq` between two types | Transparency- and unification-sensitive; even a sound probe must not be called equivalence | Support-layer probe at most; never certified output |
| 3 | Propositional (`Iff`) or semantic equivalence | — | Forbidden permanently (charter Out of Scope) |

## What rung 0 certifies

- Two artifacts with equal `statement_repr_digest` and equal `lean_version`
  audited the same elaborated statement, byte for byte in the
  notation-resistant encoding. Consumers may use this to deduplicate audit
  results, cache verdicts keyed by statement identity, or detect that a
  re-audit saw an unchanged statement.
- The digest is FNV-1a 64 (`fnv1a64:<16 hex>`) over the exact
  `raw_declaration_type_repr` bytes, computed by
  `LeanAssumptions.Render.statementReprDigest`. The full representation is
  present in the same artifact, so the digest adds no information — only a
  fixed-width comparison and pinning convenience. The field is always emitted
  by current tool versions but is schema-optional, so artifacts produced
  before the field existed remain valid inputs to delta, cluster, and
  baseline modes; a consumer must treat an absent digest as "no identity
  claim", never as a mismatch. A consumer that needs
  certainty against hash collisions compares the representations themselves.

## What rung 0 does not certify (non-assurances, HR-005)

- **Nothing across Lean versions.** Elaboration may change between
  toolchains; equal digests under different `lean_version` values carry no
  claim at all.
- **No meaning claims.** Different digests never prove the statements differ
  in meaning: alpha-renaming a binder, unfolding a definition, or reordering
  implicit arguments changes the digest while preserving meaning. Equal
  digests say nothing about the proofs, axioms, or provenance of either
  artifact.
- **Not collision-proof.** FNV-1a 64 is not cryptographic. A byte-equal
  `raw_declaration_type_repr` comparison is the authoritative rung-0 check;
  the digest is its convenient proxy. Any constructed pair of distinct
  representations with colliding digests must be treated as a reason to
  compare representations, not as an identity.
- **Not a statement-drift alarm on its own.** Delta mode already reports
  boundary-shape changes; the digest complements it and replaces nothing.

## Falsifier

Two distinct declarations whose `raw_declaration_type_repr` bytes collide
would be a soundness bug in the representation itself (FR-013), and therefore
a correctness incident under the charter — file, reproduce as a fixture, and
fix in the renderer with a regression test.

## Wording rules for docs and announcements

- Say "identity certificate" or "statement-identity digest"; never
  "equivalence", "equal statements" (without the byte-identical
  qualification), or "same theorem".
- Every public description of the digest must carry the same-`lean_version`
  qualification and must direct statement-comparison use cases to
  `comparator`.
