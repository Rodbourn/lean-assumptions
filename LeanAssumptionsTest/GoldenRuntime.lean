import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Runtime golden verification for the test driver.

The golden comparisons in `LeanAssumptionsTest/Golden/*.lean` run inside
`run_cmd` blocks at module-elaboration time, so an edit to a golden FILE alone
does not rebuild those modules and a cached `lake test` could pass against a
corrupted snapshot. This module re-runs every golden comparison at test-driver
RUNTIME, which executes on every `lake test` invocation regardless of build
caching, so golden drift can never pass silently.
-/

open Lean Elab Command

namespace LeanAssumptionsTest.GoldenRuntime

/-- Run a command-elaboration action in a freshly imported environment. -/
private def runInImportedEnv (action : CommandElabM α) : IO α := do
  Lean.initSearchPath (← Lean.findSysroot)
  let env ← Lean.importModules #[
    { module := `LeanAssumptions : Lean.Import },
    { module := `LeanAssumptionsTest.Fixtures : Lean.Import }
  ] {}
  let inputCtx := Parser.mkInputContext "" "<golden-runtime>"
  let context : Command.Context := {
    fileName := inputCtx.fileName
    fileMap := inputCtx.fileMap
    snap? := none
    cancelTk? := none
  }
  let state := Command.mkState env {} {}
  match ← EIO.toIO' ((action context).run state) with
  | .ok (value, _) => pure value
  | .error exception =>
    throw (IO.userError (← exception.toMessageData.toString))

/-- Compare rendered output against a golden file, reporting a labeled mismatch.
Live `Lean.versionString` bytes in the rendered output are normalized to
`leanVersionToken` first, matching the tokenized checked-in goldens. -/
private def compareGolden (label path rendered : String) (failures : IO.Ref (Array String)) :
    IO Unit := do
  let expected ← IO.FS.readFile path
  if expected != LeanAssumptionsTest.normalizeToolchainBytes rendered then
    failures.modify (·.push s!"{label}: rendered output does not match {path}")

/-- Re-run every golden comparison and return the list of mismatches. -/
def goldenFailures : IO (Array String) := do
  let failures ← IO.mkRef (#[] : Array String)
  let strict := LeanAssumptions.Policy.strictPolicy
  let reportPairs ← runInImportedEnv do
    let packageReport ← LeanAssumptions.Core.inspectDeclaration
      `LeanAssumptionsTest.Fixtures.packageBinder
    let quantifierReport ← LeanAssumptions.Core.inspectDeclaration
      `LeanAssumptionsTest.Fixtures.quantifierOverProp
    pure (packageReport, quantifierReport)
  let (packageReport, quantifierReport) := reportPairs
  let packageEvaluation := LeanAssumptions.Policy.evaluate strict packageReport
  let quantifierEvaluation := LeanAssumptions.Policy.evaluate strict quantifierReport
  let packageArtifact : LeanAssumptions.Render.ReportArtifact :=
    { report := packageReport, evaluation := packageEvaluation }
  compareGolden "packageBinder text" "LeanAssumptionsTest/Golden/packageBinder.txt"
    (LeanAssumptions.Render.renderText strict packageReport packageEvaluation) failures
  compareGolden "packageBinder JSON" "LeanAssumptionsTest/Golden/packageBinder.json"
    (LeanAssumptions.Render.renderJsonString strict packageReport packageEvaluation) failures
  compareGolden "packageBinder batch JSON" "LeanAssumptionsTest/Golden/packageBinder-batch.json"
    (LeanAssumptions.Render.renderBatchJsonString strict #[packageArtifact]) failures
  compareGolden "packageBinder batch text" "LeanAssumptionsTest/Golden/packageBinder-batch.txt"
    (LeanAssumptions.Render.renderBatchText strict #[packageArtifact]) failures
  compareGolden "quantifierOverProp text" "LeanAssumptionsTest/Golden/quantifierOverProp.txt"
    (LeanAssumptions.Render.renderText strict quantifierReport quantifierEvaluation) failures
  compareGolden "quantifierOverProp JSON" "LeanAssumptionsTest/Golden/quantifierOverProp.json"
    (LeanAssumptions.Render.renderJsonString strict quantifierReport quantifierEvaluation) failures
  let deltaReport ← LeanAssumptions.Delta.readDeltaReport
    "LeanAssumptionsTest/Golden/delta-baseline.json"
    "LeanAssumptionsTest/Golden/delta-current.json"
  compareGolden "delta text" "LeanAssumptionsTest/Golden/delta-report.txt"
    (LeanAssumptions.Delta.renderText deltaReport) failures
  compareGolden "delta JSON" "LeanAssumptionsTest/Golden/delta-report.json"
    (LeanAssumptions.Delta.renderJsonString deltaReport) failures
  let clusterReport ← LeanAssumptions.Cluster.readClusterReport
    "LeanAssumptionsTest/Golden/cluster-input.json"
  compareGolden "cluster text" "LeanAssumptionsTest/Golden/cluster-report.txt"
    (LeanAssumptions.Cluster.renderText clusterReport) failures
  compareGolden "cluster JSON" "LeanAssumptionsTest/Golden/cluster-report.json"
    (LeanAssumptions.Cluster.renderJsonString clusterReport) failures
  let debtText ← IO.FS.readFile "LeanAssumptionsTest/Golden/packageBinder-batch.json"
  let emptyText ← IO.FS.readFile "LeanAssumptionsTest/Golden/Baseline/empty-batch.json"
  let baselineCases := [
    ("baseline pass", debtText, debtText, "LeanAssumptionsTest/Golden/Baseline/pass-output.txt"),
    ("baseline regression", emptyText, debtText,
      "LeanAssumptionsTest/Golden/Baseline/regression-output.txt"),
    ("baseline improvement", debtText, emptyText,
      "LeanAssumptionsTest/Golden/Baseline/improvement-output.txt")
  ]
  for (label, baselineText, currentText, goldenPath) in baselineCases do
    match LeanAssumptions.Baseline.compareArtifactStrings baselineText currentText with
    | .ok comparison =>
      compareGolden label goldenPath (LeanAssumptions.Baseline.renderText comparison) failures
    | .error error =>
      failures.modify (·.push s!"{label}: comparison failed: {error}")
  failures.get

end LeanAssumptionsTest.GoldenRuntime
