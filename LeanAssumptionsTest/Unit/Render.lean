import Lean.Data.Json.Parser
import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for renderer-specific support behavior that is not visible from the
trusted core alone.
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
  -- The streaming CLI text path prints per-report text plus the summary
  -- block; that composition must stay byte-identical to renderBatchText.
  let artifact : ReportArtifact := {
    report := controlLiteralReport
    evaluation := { result := .pass, findings := #[] }
  }
  let artifacts := #[artifact, artifact]
  let streamed :=
    (Render.renderText strictPolicy artifact.report artifact.evaluation) ++ "\n" ++
    (Render.renderText strictPolicy artifact.report artifact.evaluation) ++
    Render.renderBatchSummaryTextBlock artifacts
  assertEq "streamed text equals batch text"
    (Render.renderBatchText strictPolicy artifacts) streamed

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

/-- A minimal report over a known constant head, for statement-digest pinning. -/
private def natHeadedReport : AssumptionReport :=
  let natExpr := Lean.Expr.const `Nat []
  {
    declarationName := `LeanAssumptionsTest.NatHeaded
    declarationKind := .definition
    declarationType := natExpr
    binders := #[]
    resultType := natExpr
    transparencyMode := .none
  }

run_cmd do
  -- Rung-0 statement-identity digest: exactly FNV-1a 64 over the
  -- raw_declaration_type_repr bytes, carrying the shared fnv1a64: prefix.
  assertEq "statement digest hashes the raw repr bytes"
    ("fnv1a64:" ++ Policy.fnv1a64Hex "const(Nat,[])")
    (Render.statementReprDigest natHeadedReport)
  assertEq "statement digest is deterministic"
    (Render.statementReprDigest natHeadedReport)
    (Render.statementReprDigest natHeadedReport)
  assertTrue "different statements get different digests"
    (!(Render.statementReprDigest natHeadedReport ==
       Render.statementReprDigest controlLiteralReport))
  let rendered := Render.renderJsonString strictPolicy natHeadedReport {
    result := .pass
    findings := #[]
  }
  let needle := "\"statement_repr_digest\":\"" ++ Render.statementReprDigest natHeadedReport ++ "\""
  assertTrue "rendered JSON carries the statement digest"
    ((rendered.splitOn needle).length > 1)
  let renderedText := Render.renderText strictPolicy natHeadedReport {
    result := .pass
    findings := #[]
  }
  let textNeedle := "statement_repr_digest: " ++ Render.statementReprDigest natHeadedReport
  assertTrue "rendered text carries the statement digest"
    ((renderedText.splitOn textNeedle).length > 1)
