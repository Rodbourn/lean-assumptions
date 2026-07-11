import Lean

/-!
Core report-model definitions for assumption-surface analysis.

These data types are part of the certified classification path. They are kept
small and explicit so recursive classification and policy evaluation can remain
auditable.
-/

namespace LeanAssumptions.Core

/-- Transparency modes tracked by reports and future policies. -/
inductive TransparencyMode where
  | none
  | reducible
  | recursiveNormalization
  deriving DecidableEq, Repr, Inhabited

/-- A normalized declaration-kind view for audit reports. -/
inductive DeclarationKind where
  | theorem
  | definition
  | axiom
  | opaque
  | quotient
  | inductive
  | constructor
  | recursor
  | other
  deriving DecidableEq, Repr, Inhabited

/-- The outer-binder kinds visible at the theorem surface. -/
inductive SurfaceBinderKind where
  | explicit
  | implicit
  | strictImplicit
  | instanceImplicit
  deriving DecidableEq, Repr, Inhabited

/-- The mandatory public assumption categories for stable reports. -/
inductive AssumptionCategory where
  | pureData
  | directProp
  | proofCarryingData
  | packageWithPropFields
  | typeclassAssumption
  | alias
  | unknown
  deriving DecidableEq, Repr, Inhabited

/-- Secondary classification flags preserved alongside the primary category. -/
inductive AssumptionFlag where
  | binderTypeIsProp
  | binderQuantifiesOverProp
  | instanceBinder
  | cycleTruncated
  deriving DecidableEq, Repr, Inhabited

/-- Summary for a binder or package field at the theorem surface. -/
structure BinderSurface where
  userName : Lean.Name
  binderType : Lean.Expr
  binderKind : SurfaceBinderKind
  primaryCategory : AssumptionCategory
  secondaryFlags : Array AssumptionFlag := #[]
  children : Array BinderSurface := #[]
  deriving Repr

/--
Declaration assumption-surface report.

This report includes declaration lookup, binder peeling, result-type recovery,
recursive structure/class field expansion, proof-carrying-data wrapper
detection, and explicit cycle/unknown flags. Policy evaluation is kept in the
separate certified policy layer.

`resultSurface?` is present only when binder peeling stopped at a blocked
result surface: an alias-headed remainder that could hide further binders
under the report transparency mode, or a peeling-fuel exhaustion. A fully
peeled result carries `none`.

`transparencyLimited` is `true` when the report contains at least one
unexpanded `alias` node, meaning classification depends materially on the
chosen transparency mode: a more permissive mode would expand those heads and
could classify them differently.
-/
structure AssumptionReport where
  declarationName : Lean.Name
  declarationKind : DeclarationKind
  declarationType : Lean.Expr
  binders : Array BinderSurface
  resultType : Lean.Expr
  transparencyMode : TransparencyMode
  unknownsOccurred : Bool := false
  cyclesTruncated : Bool := false
  resultSurface? : Option BinderSurface := none
  transparencyLimited : Bool := false
  deriving Repr

end LeanAssumptions.Core
