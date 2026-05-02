# Phase 1 Behavioral Spec

This document is the concrete behavioral spec for the Phase 1 certified path.

Implemented behavior:

- inspect a named declaration visible in the current environment
- recover the declaration name
- recover the declaration kind in a normalized form
- recover the elaborated declaration type
- recover the peeled result type after outer binders are removed
- report transparency mode as `none`
- report `unknownsOccurred = false` and `cyclesTruncated = false`
- peel all outer `forall` binders in order
- classify each peeled binder as explicit, implicit, strict implicit, or instance implicit
- preserve each peeled binder's user-facing name, elaborated type, primary category, and secondary flags
- classify each binder conservatively at the outer surface:
  - `typeclass_assumption` if the binder is instance implicit
  - `direct_prop` if a non-instance binder type is itself a proposition or if the binder ranges over `Prop`
  - `pure_data` otherwise
- emit `binderTypeIsProp` for direct proposition surface binders
- emit `instanceBinder` for instance-implicit binders

Phase 1 boundary at the time this milestone closed:

Later phases may implement items listed here; current repository status is
tracked in `docs/requirements-status.md` and `docs/phase2-spec.md`.

- no recursive structure or class expansion yet
- no proof-carrying data descent yet
- no alias transparency beyond tracking the mode field in the report model
- no policy evaluation yet
- no rendering or JSON output yet

Verified gates for the Phase 1 surface:

- `lake build`
- `lake test`
- `lake lint`
- `lake env leanchecker --fresh LeanAssumptions`
- `python scripts/check_coverage_ledger.py`

The corresponding tests live in:

- `LeanAssumptionsTest/Unit/Core/Phase1.lean`
- `LeanAssumptionsTest/Integration/Phase1.lean`
