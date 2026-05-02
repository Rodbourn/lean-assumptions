/-!
Phase 1 fixture declarations covering binder peeling and direct proposition
classification.
-/
namespace LeanAssumptionsTest.Fixtures

/-- A theorem with an explicit proposition binder and an explicit proof binder. -/
theorem explicitProp (p : Prop) (h : p) : p := h

/-- A theorem with implicit proposition and proof binders. -/
theorem implicitProp {p : Prop} {h : p} : p := h

/-- A theorem with strict-implicit proposition and proof binders. -/
theorem strictImplicitProp ⦃p : Prop⦄ ⦃h : p⦄ : p := h

/-- A theorem with all outer binder kinds represented at least once. -/
theorem allBinderKinds {α : Type} ⦃p : Prop⦄ [inst : Inhabited α] (x : α) (h : p) : x = x := by
  let _ := inst
  let _ : p := h
  rfl

/-- A plain data theorem used to distinguish pure data from proposition binders. -/
theorem pureDataOnly (n : Nat) : n = n := rfl

/-- A simple definition fixture for declaration-kind recovery. -/
def plainDefinition (n : Nat) : Nat := n + 1

end LeanAssumptionsTest.Fixtures
