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

/-- Placeholder token stored in checked-in goldens wherever rendered output
embeds the live `Lean.versionString`, so one golden set validates every
toolchain in the compatibility matrix. -/
def leanVersionToken : String := "<LEAN_VERSION>"

/-- Replace every exact occurrence of the live toolchain's `Lean.versionString`
with `leanVersionToken`. Applied to ACTUAL rendered output before golden
comparison — never to emitted artifacts, whose `lean_version` must stay real
(charter output requirements). Non-version bytes are untouched, so any other
cross-toolchain drift still fails the golden gates. -/
def normalizeToolchainBytes (s : String) : String :=
  s.replace Lean.versionString leanVersionToken

end LeanAssumptionsTest
