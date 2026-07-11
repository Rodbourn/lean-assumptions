import LeanAssumptionsTest.Fixtures.Corpus

/-!
Adversarial fixture corpus for conservative-classification coverage.

These declarations cover statement shapes that historically misclassified as
`pure_data` and passed strict policy (2026-07-11 audit): `let`-wrapped binder
types, non-structure inductive types that carry proofs, function types into
proof-carrying data, packages with alias-hidden fields, and opaque type heads.
Negative controls that must stay `pure_data` are included so conservatism
fixes cannot silently overreach.
-/
namespace LeanAssumptionsTest.Fixtures

/-- A non-structure inductive type whose only constructor carries a proof. -/
inductive HiddenProofCarrier (p : Prop) : Type where
  /-- Wrap a proof of `p` as data. -/
  | intro (h : p)

/-- A structure whose only field hides a package behind a reducible alias. -/
structure AliasFieldPackage where
  inner : ProofPackageAlias Nat

/-- An opaque type constant reserved for fixture-only unknown-head tests. -/
opaque OpaqueCarrier : Type := Nat

/-- A theorem whose binder type hides a package behind a `let` wrapper. -/
theorem letWrappedPackageBinder (pkg : (let T := ProofPackage Nat; T)) : True := by
  let _ := pkg
  trivial

/-- A theorem whose binder is a non-structure inductive carrying a proof. -/
theorem inductiveProofCarrierBinder (x : HiddenProofCarrier (1 = 1)) : True := by
  let _ := x
  trivial

/-- A theorem whose binder is a function into proof-carrying data. -/
theorem functionIntoSubtypeBinder (f : Unit → {n : Nat // n = n}) : True := by
  let _ := f
  trivial

/-- A theorem whose binder is a function into plain data. -/
theorem functionIntoDataBinder (f : Nat → Nat) : True := by
  let _ := f
  trivial

/-- A theorem whose binder is a recursive inductive over plain data. -/
theorem listDataBinder (xs : List Nat) : True := by
  let _ := xs
  trivial

/-- A theorem whose binder is a recursive inductive over proof-carrying data. -/
theorem listOfProofCarriersBinder (xs : List (HiddenProofCarrier (1 = 1))) : True := by
  let _ := xs
  trivial

/-- A theorem whose binder is a package with an alias-hidden field. -/
theorem aliasFieldPackageBinder (pkg : AliasFieldPackage) : True := by
  let _ := pkg
  trivial

/-- A theorem whose binder head is an opaque type constant. -/
theorem opaqueHeadBinder (x : OpaqueCarrier) : True := by
  let _ := x
  trivial

/-- A plain definition alias that hides a package. -/
def PlainDefPackageAlias := ProofPackage Nat

/-- A reducible-attribute definition alias that hides a package. -/
@[reducible] def ReducibleDefPackageAlias := ProofPackage Nat

/-- A theorem whose binder hides a package behind a plain `def` alias. -/
theorem defAliasPackageBinder (pkg : PlainDefPackageAlias) : True := by
  let _ := pkg
  trivial

/-- A theorem whose binder hides a package behind a `@[reducible] def` alias. -/
theorem reducibleDefAliasPackageBinder (pkg : ReducibleDefPackageAlias) : True := by
  let _ := pkg
  trivial

/-- A proposition abbreviation used to pin alias-versus-proposition precedence. -/
abbrev TrivialHypAlias : Prop := 1 = 1

/-- An abbreviation that hides an entire statement surface. -/
abbrev HiddenStatementAlias : Prop := ∀ _ : 1 = 1, True

/-- A theorem whose full statement hides behind an abbreviation. -/
theorem aliasHiddenStatement : HiddenStatementAlias := fun _ => trivial

/-- A theorem whose binder nests the same generic structure head. -/
theorem nestedTupleBinder (p : Nat × Nat × Nat) : True := by
  let _ := p
  trivial

/-- A theorem whose binder pairs two proof-carrying packages. -/
theorem pairOfPackagesBinder (p : ProofPackage Nat × ProofPackage Nat) : True := by
  let _ := p
  trivial

/-- A tuple type nested beyond the certified expansion-fuel bound of 64. -/
abbrev DeepTuple : Type :=
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat ×
  Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat × Nat

/-- A theorem whose binder exhausts recursive expansion fuel. -/
theorem deepTupleBinder (p : DeepTuple) : True := by
  let _ := p
  trivial

/-- A definition that hides an entire statement surface. -/
def HiddenStatementDef : Prop := ∀ _ : 1 = 1, True

/-- A theorem whose full statement hides behind a definition. -/
theorem defHiddenStatement : HiddenStatementDef := fun _ => trivial

/-- A theorem whose proof binder spells its proposition through an alias. -/
theorem propAliasBinder (h : TrivialHypAlias) : True := by
  let _ := h
  trivial

end LeanAssumptionsTest.Fixtures
