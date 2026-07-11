import Lean.Data.Json.Parser
import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for renderer-specific support behavior that is not visible from the
certified core alone.
-/

open LeanAssumptions
open LeanAssumptions.Core
open LeanAssumptions.Policy
open LeanAssumptions.Render
open LeanAssumptionsTest

/-- A string containing C0 controls that JSON must not emit raw. -/
private def controlString : String :=
  String.ofList [Char.ofNat 1, 'x', Char.ofNat 8]

/-- A report whose rendered expression representation contains a control string literal. -/
private def controlLiteralReport : AssumptionReport :=
  let literalExpr := Lean.Expr.lit (Lean.Literal.strVal controlString)
  {
    declarationName := `LeanAssumptionsTest.ControlLiteral
    declarationKind := .definition
    declarationType := literalExpr
    binders := #[
      {
        userName := `s
        binderType := literalExpr
        binderKind := .explicit
        primaryCategory := .pureData
      }
    ]
    resultType := literalExpr
    transparencyMode := .none
  }

run_cmd do
  assertEq "JSON escape covers non-short C0 controls"
    "\\u0001x\\u0008"
    (JsonUtil.escapeString controlString)
  match Lean.Json.parse (JsonUtil.quoteString controlString) with
  | .ok _ => pure ()
  | .error error => throwError "quoted control string did not parse as JSON: {error}"

run_cmd do
  let rendered := Render.renderJsonString strictPolicy controlLiteralReport {
    result := .pass
    findings := #[]
  }
  match Lean.Json.parse rendered with
  | .ok _ => pure ()
  | .error error => throwError "rendered report with control literal did not parse as JSON: {error}"

/-- A report whose binder name attempts to forge a report line via a newline. -/
private def forgedNameReport : AssumptionReport :=
  let dataExpr := Lean.Expr.sort Lean.Level.zero
  {
    declarationName := Lean.Name.mkSimple "evil\ntarget: forged"
    declarationKind := .theorem
    declarationType := dataExpr
    binders := #[
      {
        userName := Lean.Name.mkSimple "x\npolicy_result: pass"
        binderType := dataExpr
        binderKind := .explicit
        primaryCategory := .pureData
      }
    ]
    resultType := dataExpr
    transparencyMode := .none
  }

run_cmd do
  -- Text reports must be line-injection-proof: a hostile name may never
  -- fabricate a report line such as a second `policy_result:` entry.
  let rendered := Render.renderText strictPolicy forgedNameReport {
    result := .fail
    findings := #[]
  }
  assertEq "text report has exactly one policy_result line"
    2 (rendered.splitOn "\npolicy_result:").length
  assertEq "text report has exactly one target line"
    2 (rendered.splitOn "\ntarget:").length
  assertTrue "newline in name is escaped, not emitted"
    ((rendered.splitOn "evil\\ntarget").length == 2)
