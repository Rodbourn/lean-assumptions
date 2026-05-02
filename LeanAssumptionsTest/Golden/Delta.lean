import LeanAssumptions.Delta
import LeanAssumptionsTest.TestUtil

/-!
Golden tests for stable delta reporting.

These tests specify the FR-016 public support-layer contract before the delta
implementation. Delta mode compares rendered JSON artifacts and does not
re-enter the certified classification path.
-/

open LeanAssumptionsTest

private def baselinePath : System.FilePath :=
  "LeanAssumptionsTest/Golden/delta-baseline.json"

private def currentPath : System.FilePath :=
  "LeanAssumptionsTest/Golden/delta-current.json"

run_cmd do
  let report ← LeanAssumptions.Delta.readDeltaReport baselinePath currentPath
  assertEq "delta change count" 4 report.changes.size
  let first ← requireAt "first delta change" report.changes 0
  assertEq "first delta target" "Example.added" first.target
  assertEq "delta changed declarations" 2 report.summary.declarationsChanged
  assertEq "delta result changes" 1 report.summary.policyResultChanged
  assertEq "delta category changes" 2 report.summary.findingCategoriesChanged
  assertEq "delta boundary changes" 1 report.summary.boundaryShapeChanged

run_cmd do
  let report ← LeanAssumptions.Delta.readDeltaReport baselinePath currentPath
  let actual := LeanAssumptions.Delta.renderText report
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/delta-report.txt"
  assertEq "delta text golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Delta.readDeltaReport baselinePath currentPath
  let actual := LeanAssumptions.Delta.renderJsonString report
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/delta-report.json"
  assertEq "delta JSON golden" expected actual
