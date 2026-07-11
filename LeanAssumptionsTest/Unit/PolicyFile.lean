import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for the versioned JSON policy-file parser (FR-011).

The parser is public CLI API: exact-name patterns are the default, prefix
patterns must be explicit objects, and every malformed input must be an
explicit error rather than a silent default.
-/

open Lean Elab Command
open LeanAssumptions
open LeanAssumptions.Policy
open LeanAssumptionsTest

/-- Parse a policy JSON string or fail the test with the parse error. -/
private def parsePolicyForTest (label text : String) : CommandElabM PolicyConfig := do
  let json ←
    match Lean.Json.parse text with
    | .ok json => pure json
    | .error error => throwError "{label}: JSON parse failed: {error}"
  match Cli.parsePolicyJson json with
  | .ok policy => pure policy
  | .error error => throwError "{label}: policy parse failed: {error}"

/-- Assert that a policy JSON string is rejected by the parser. -/
private def assertPolicyRejected (label text : String) : CommandElabM Unit := do
  let json ←
    match Lean.Json.parse text with
    | .ok json => pure json
    | .error error => throwError "{label}: JSON parse failed: {error}"
  match Cli.parsePolicyJson json with
  | .ok _ => throwError "{label}: expected the parser to reject this policy"
  | .error _ => pure ()

run_cmd do
  let policy ← parsePolicyForTest "full policy" <|
    "{\"version\":1,\"identifier\":\"example\",\"transparency_mode\":\"reducible\"," ++
    "\"permit_direct_props\":[\"My.Hyp\",{\"exact\":\"My.Other\"}]," ++
    "\"permit_package_types\":[{\"prefix\":\"My.Safe\"}]," ++
    "\"typeclass_policy\":\"warn\",\"unknown_policy\":\"allow\"}"
  assertEq "full policy identifier" "example" policy.identifier
  assertEq "full policy transparency" Core.TransparencyMode.reducible policy.transparencyMode
  assertEq "full policy direct count" 2 policy.permittedDirectProps.size
  let firstDirect ← requireAt "full policy first direct" policy.permittedDirectProps 0
  assertEq "full policy string spelling is exact" (NamePattern.exact `My.Hyp) firstDirect
  let secondDirect ← requireAt "full policy second direct" policy.permittedDirectProps 1
  assertEq "full policy object exact spelling" (NamePattern.exact `My.Other) secondDirect
  let package ← requireAt "full policy package" policy.permittedPackageTypes 0
  assertEq "full policy explicit prefix" (NamePattern.prefix `My.Safe) package
  assertEq "full policy typeclass treatment" AssumptionTreatment.warn policy.typeclassPolicy
  assertEq "full policy unknown treatment" AssumptionTreatment.allow policy.unknownPolicy
  assertEq "full policy alias treatment" AssumptionTreatment.fail policy.aliasPolicy

run_cmd do
  let policy ← parsePolicyForTest "minimal policy" "{\"version\":1}"
  assertEq "minimal policy identifier" "policy-file" policy.identifier
  assertEq "minimal policy transparency" Core.TransparencyMode.none policy.transparencyMode
  assertEq "minimal policy direct count" 0 policy.permittedDirectProps.size
  assertEq "minimal policy typeclass treatment" AssumptionTreatment.fail policy.typeclassPolicy
  assertEq "minimal policy unknown treatment" AssumptionTreatment.fail policy.unknownPolicy

run_cmd do
  assertPolicyRejected "missing version" "{}"
  assertPolicyRejected "wrong version" "{\"version\":2}"
  assertPolicyRejected "non-numeric version" "{\"version\":\"1\"}"
  assertPolicyRejected "bad transparency" "{\"version\":1,\"transparency_mode\":\"everything\"}"
  assertPolicyRejected "bad treatment" "{\"version\":1,\"unknown_policy\":\"maybe\"}"
  assertPolicyRejected "bad pattern object"
    "{\"version\":1,\"permit_direct_props\":[{\"regex\":\"My.*\"}]}"
  assertPolicyRejected "non-array patterns" "{\"version\":1,\"permit_direct_props\":\"My.Hyp\"}"
  assertPolicyRejected "non-object policy" "[1]"
