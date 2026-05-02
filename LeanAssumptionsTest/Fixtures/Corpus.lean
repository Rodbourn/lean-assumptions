/-!
Future-phase fixture corpus required by the charter.

These declarations intentionally cover package expansion, proof-carrying data,
aliases, cycles, suspicious constructs, and examples that distinguish theorem
statement assumptions from proof validity concerns.
-/
namespace LeanAssumptionsTest.Fixtures

/-- A structure with a proposition-valued field and a proof witness. -/
structure ProofPackage (α : Type) where
  carrier : α
  certified : Prop
  witness : certified

/-- A nested package used for recursive expansion tests. -/
structure NestedPackage (α : Type) where
  inner : ProofPackage α

/-- A class carrying a proposition-valued field and witness proof. -/
class PayloadClass (α : Type) where
  certified : Prop
  witness : certified

/-- A reducible alias that hides a proposition-bearing package. -/
abbrev ProofPackageAlias (α : Type) := ProofPackage α

/-- A theorem whose binder is a structure with proposition fields. -/
theorem packageBinder (pkg : ProofPackage Nat) : pkg.carrier = pkg.carrier := rfl

/-- A theorem whose binder is a nested structure with proposition fields. -/
theorem nestedPackageBinder (pkg : NestedPackage Nat) : pkg.inner.carrier = pkg.inner.carrier := rfl

/-- A theorem whose binder is an instance-implicit proposition-bearing class. -/
theorem classBinder {α : Type} [inst : PayloadClass α] (x : α) : x = x := by
  let _ := inst
  rfl

/-- A theorem whose binder is a reducible alias hiding a package. -/
theorem aliasBinder (pkg : ProofPackageAlias Nat) : pkg.carrier = pkg.carrier := rfl

/-- A theorem whose binder is a `Subtype` carrying a proof. -/
theorem subtypeBinder (x : {n : Nat // n = n}) : x.1 = x.1 := rfl

/-- A theorem whose binder is a `Sigma` carrying lifted proof data. -/
theorem sigmaBinder (x : Sigma fun n : Nat => PLift (n = n)) : x.1 = x.1 := rfl

/-- A theorem whose binder is a `PSigma` carrying proof data directly. -/
theorem psigmaBinder (x : PSigma fun n : Nat => n = n) : x.1 = x.1 := rfl

/-- A theorem whose statement has no proposition-bearing binders. -/
theorem noPropBearingAssumptions (n : Nat) : n = n := rfl

mutual

/-- The left side of a mutually recursive package graph. -/
structure CyclicLeft where
  right : CyclicRight

/-- The right side of a mutually recursive package graph with a proposition field. -/
structure CyclicRight where
  left : CyclicLeft
  certified : True

end

/-- A theorem whose binder enters the cyclic package graph. -/
theorem cyclicPackageBinder (x : CyclicLeft) : True := by
  let _ := x
  trivial

/-- A suspicious axiom fixture reserved for fixture-only tests. -/
axiom suspiciousTruth : True

/-- A suspicious opaque fixture reserved for fixture-only tests. -/
opaque suspiciousOpaque : Nat := 0

/-- A theorem with statement-surface assumptions but an ordinary proof. -/
theorem statementSurfaceAssumption (h : True) : True := h

/-- A theorem with no statement-surface assumptions but an axiom-based proof. -/
theorem proofDependsOnAxiom : True := suspiciousTruth

end LeanAssumptionsTest.Fixtures
