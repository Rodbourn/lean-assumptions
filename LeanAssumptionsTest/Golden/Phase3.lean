import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Phase 3 golden tests for stable text and JSON rendering.

These tests define the first public rendering contract before the renderer
implementation lands. Command and CLI adapters must stay thin over these
renderers.
-/

open LeanAssumptions
open LeanAssumptions.Policy
open LeanAssumptions.Render
open LeanAssumptionsTest

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  let evaluation := Policy.evaluate Policy.strictPolicy report
  let actual := Render.renderText Policy.strictPolicy report evaluation
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/packageBinder.txt"
  assertEq "packageBinder text golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  let evaluation := Policy.evaluate Policy.strictPolicy report
  let actual := Render.renderJsonString Policy.strictPolicy report evaluation
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/packageBinder.json"
  assertEq "packageBinder JSON golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  let evaluation := Policy.evaluate Policy.strictPolicy report
  let actual := Render.renderBatchJsonString Policy.strictPolicy #[
    { report := report, evaluation := evaluation }
  ]
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/packageBinder-batch.json"
  assertEq "packageBinder batch JSON golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.quantifierOverProp
  let evaluation := Policy.evaluate Policy.strictPolicy report
  let actual := Render.renderText Policy.strictPolicy report evaluation
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/quantifierOverProp.txt"
  assertEq "quantifierOverProp text golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.quantifierOverProp
  let evaluation := Policy.evaluate Policy.strictPolicy report
  let actual := Render.renderJsonString Policy.strictPolicy report evaluation
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/quantifierOverProp.json"
  assertEq "quantifierOverProp JSON golden" expected actual
