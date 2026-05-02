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
