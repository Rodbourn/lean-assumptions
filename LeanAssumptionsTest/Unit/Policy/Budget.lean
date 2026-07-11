import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for the certified policy engine's conservative-failure branch:
exceeding the deterministic traversal budget must yield an `audit_error`
rather than a silently truncated evaluation.
-/

open Lean Elab Command
open LeanAssumptions
open LeanAssumptions.Core
open LeanAssumptions.Policy
open LeanAssumptionsTest

/-- A pure-data node used to synthesize oversized report trees. -/
private def pureDataNode : BinderSurface := {
  userName := `payload
  binderType := Lean.Expr.sort Lean.Level.zero
  binderKind := .explicit
  primaryCategory := .pureData
}

/-- Synthesize a report whose tree has one root with `width` pure-data children. -/
private def wideReport (width : Nat) : AssumptionReport := {
  declarationName := `SyntheticBudget.target
  declarationKind := .theorem
  declarationType := Lean.Expr.sort Lean.Level.zero
  binders := #[{ pureDataNode with userName := `root, children := .replicate width pureDataNode }]
  resultType := Lean.Expr.sort Lean.Level.zero
  transparencyMode := .none
}

run_cmd do
  -- Inside the budget: an all-pure-data tree passes strict policy.
  let evaluation := Policy.evaluate Policy.strictPolicy (wideReport 100)
  assertEq "within budget result" PolicyResult.pass evaluation.result
  assertEq "within budget finding count" 0 evaluation.findings.size

run_cmd do
  -- Beyond the budget: evaluation must stop with an explicit audit error,
  -- never a silently truncated pass.
  let evaluation := Policy.evaluate Policy.strictPolicy (wideReport 10001)
  assertEq "over budget result" PolicyResult.auditError evaluation.result
  let finding ← requireAt "over budget finding" evaluation.findings 0
  assertEq "over budget finding kind"
    PolicyFindingKind.policyTraversalBudgetExceeded finding.kind
  assertEq "over budget severity" PolicySeverity.auditError finding.severity
