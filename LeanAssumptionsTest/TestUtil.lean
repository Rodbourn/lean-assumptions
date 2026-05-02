import Lean

/-!
Shared test helpers for compile-time Lean assertions.
-/

open Lean Elab Command

namespace LeanAssumptionsTest

/-- Fail the current compile-time test if the condition does not hold. -/
def assertTrue (label : String) (condition : Bool) : CommandElabM Unit := do
  unless condition do
    throwError "{label}"

/-- Fail the current compile-time test if the two values are not equal. -/
def assertEq [BEq α] [Repr α] (label : String) (expected actual : α) : CommandElabM Unit := do
  unless expected == actual do
    throwError "{label}: expected {repr expected}, got {repr actual}"

/-- Retrieve an array element or fail the current compile-time test. -/
def requireAt (label : String) (xs : Array α) (index : Nat) : CommandElabM α := do
  match xs[index]? with
  | some value => pure value
  | none => throwError "{label}: missing array entry at index {index}"

end LeanAssumptionsTest
