import Lean.Data.Json.Parser
import LeanAssumptions.Baseline
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for baseline finding identity.

Baseline mode tracks rendered policy findings by the documented statement-surface
identity. These tests keep that identity small and stable: severity and rendered
expressions are excluded, while declaration names and finding paths are part of
the comparison key.
-/

open Lean Elab Command
open LeanAssumptions.Baseline
open LeanAssumptionsTest

/-- Parse a finding JSON object for direct identity-contract assertions. -/
private def parseFindingForTest
    (label declarationName text : String) : CommandElabM FindingIdentity := do
  let json ←
    match Lean.Json.parse text with
    | .ok json => pure json
    | .error error => throwError "{label}: JSON parse failed: {error}"
  match parseFindingIdentity declarationName json with
  | .ok finding => pure finding
  | .error error => throwError "{label}: finding parse failed: {error}"

run_cmd do
  let warning ← parseFindingForTest "warning finding" "Example.same"
    "{\"kind\":\"unapproved_direct_prop\",\"severity\":\"warning\",\"path\":[\"h\"],\"category\":\"direct_prop\",\"type_name\":null}"
  let failure ← parseFindingForTest "failure finding" "Example.same"
    "{\"kind\":\"unapproved_direct_prop\",\"severity\":\"failure\",\"path\":[\"h\"],\"category\":\"direct_prop\",\"type_name\":null}"
  assertEq "baseline identity ignores severity" warning failure

run_cmd do
  let original : FindingIdentity := {
    declarationName := "Example.same"
    kind := "unapproved_direct_prop"
    category := "direct_prop"
    path := #["h"]
    typeName? := none
  }
  let reorderedPath := { original with path := #["later", "h"] }
  let renamedDeclaration := { original with declarationName := "Example.renamed" }
  assertTrue "baseline identity includes finding path" (!(original == reorderedPath))
  assertTrue "baseline identity includes declaration name" (!(original == renamedDeclaration))
