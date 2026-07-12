import LeanAssumptions.Baseline
import LeanAssumptionsTest.TestUtil

/-!
Golden tests for stable baseline comparison output.

Baseline mode consumes ordinary batch JSON artifacts and assigns CI semantics to
the same finding identities used for comparison. These tests cover pass,
regression, improvement, and schema-version failure.
-/

open LeanAssumptions.Baseline
open LeanAssumptionsTest

private def debtPath : System.FilePath :=
  "LeanAssumptionsTest/Golden/packageBinder-batch.json"

private def emptyPath : System.FilePath :=
  "LeanAssumptionsTest/Golden/Baseline/empty-batch.json"

/-- Read and compare two golden batch artifacts. -/
private def readComparison
    (baselinePath currentPath : System.FilePath) : IO BaselineComparison := do
  let baselineText ← IO.FS.readFile baselinePath
  let currentText ← IO.FS.readFile currentPath
  match compareArtifactStrings baselineText currentText with
  | .ok comparison => pure comparison
  | .error error => throw (IO.userError error)

run_cmd do
  let comparison ← readComparison debtPath debtPath
  assertEq "baseline pass status" BaselineStatus.pass comparison.status
  assertEq "baseline pass exit" (0 : UInt32) comparison.exitCode
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/Baseline/pass-output.txt"
  assertEq "baseline pass text golden" expected (normalizeToolchainBytes (renderText comparison))

run_cmd do
  let comparison ← readComparison emptyPath debtPath
  assertEq "baseline regression status" BaselineStatus.regression comparison.status
  assertEq "baseline regression exit" (1 : UInt32) comparison.exitCode
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/Baseline/regression-output.txt"
  assertEq "baseline regression text golden" expected (normalizeToolchainBytes (renderText comparison))

run_cmd do
  let comparison ← readComparison debtPath emptyPath
  assertEq "baseline improvement status" BaselineStatus.improvement comparison.status
  assertEq "baseline improvement exit" (0 : UInt32) comparison.exitCode
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/Baseline/improvement-output.txt"
  assertEq "baseline improvement text golden" expected (normalizeToolchainBytes (renderText comparison))

run_cmd do
  let currentText ← IO.FS.readFile emptyPath
  let mismatchedBaseline :=
    "{\"schema_version\":\"0\",\"tool_version\":\"0.1.0-dev\",\"lean_version\":\"4.30.0-rc2\",\"policy_identifier\":\"strict\",\"transparency_mode\":\"none\",\"summary\":{\"declarations_scanned\":0,\"declarations_passed\":0,\"declarations_warned\":0,\"declarations_failed\":0,\"declarations_with_unknown_nodes\":0,\"schema_version\":\"1\"},\"reports\":[]}"
  match compareArtifactStrings mismatchedBaseline currentText with
  | .ok _ => throwError "baseline schema mismatch unexpectedly succeeded"
  | .error error =>
    assertEq "baseline schema mismatch message"
      "baseline schema_version 0 does not match current schema_version 1; regenerate the baseline"
      error
