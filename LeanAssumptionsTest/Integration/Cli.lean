import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Integration tests for the Phase 3 CLI support API.

The Lake executable is a thin wrapper around `LeanAssumptions.Cli.run`; these
tests exercise argument parsing, module imports, declaration lists, module
scans, policy files, output modes, and policy exit codes.
-/

open Lean Elab Command
open LeanAssumptionsTest

/-- Imports shared by the quiet CLI integration checks. -/
private def cliTestImports : Array Lean.Import :=
  #[
    { module := `LeanAssumptions : Lean.Import },
    { module := `LeanAssumptionsTest.Fixtures : Lean.Import },
    { module := `LeanAssumptionsTest.Fixtures.Phase1 : Lean.Import }
  ]

/--
Import the CLI test environment once so repeated argument/exit-code checks do
not repeatedly load the same fixture modules during compilation.
-/
private def importCliTestEnv : IO (Lean.Environment × Lean.Options) := do
  let opts : Lean.Options := {}
  Lean.initSearchPath (← Lean.findSysroot)
  let env ← Lean.importModules cliTestImports opts
  pure (env, opts)

/-- Assert a CLI exit code while suppressing repeated report output. -/
private def assertCliExit
    (env : Lean.Environment)
    (opts : Lean.Options)
    (label : String)
    (expected : UInt32)
    (args : Array String) : CommandElabM Unit := do
  let code ← LeanAssumptions.Cli.runWithImportedEnv env opts args false
  assertEq label expected code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "text",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage"
  ]
  assertEq "CLI public import path exit" 0 code

run_cmd do
  let (env, opts) ← importCliTestEnv
  assertCliExit env opts "CLI strict package failure exit" 1 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json"
  ]
  assertCliExit env opts "CLI policy file exit" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "text",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-allow-package.json"
  ]
  assertCliExit env opts "CLI declaration list exit" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.noPropBearingAssumptions",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage"
  ]
  assertCliExit env opts "CLI module scan strict exit" 1 #[
    "--module", "LeanAssumptionsTest.Fixtures.Phase1",
    "--scan-module", "LeanAssumptionsTest.Fixtures.Phase1",
    "--format", "json"
  ]
  assertCliExit env opts "CLI reducible alias policy exit" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.aliasBinder",
    "--format", "json",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-reducible-allow-package.json"
  ]
  assertCliExit env opts "CLI allow flags compose before --policy" 0 #[
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-strict.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json"
  ]
  assertCliExit env opts "CLI strict policy file alone fails" 1 #[
    "--policy", "LeanAssumptionsTest/Fixtures/policy-strict.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json"
  ]
  assertCliExit env opts "CLI duplicate --policy rejected" 2 #[
    "--policy", "LeanAssumptionsTest/Fixtures/policy-strict.json",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-allow-package.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder"
  ]
  assertCliExit env opts "CLI unknown option exit" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--frobnicate"
  ]
  assertCliExit env opts "CLI incomplete option exit" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl"
  ]
  assertCliExit env opts "CLI bad format exit" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "yaml"
  ]
  assertCliExit env opts "CLI missing module exit" 2 #[
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder"
  ]
  assertCliExit env opts "CLI missing work exit" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures"
  ]
  assertCliExit env opts "CLI unknown declaration exit" 1 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.doesNotExist"
  ]
  assertCliExit env opts "CLI malformed policy file exit" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--policy", "LeanAssumptionsTest/Golden/packageBinder.txt"
  ]
  assertCliExit env opts "CLI missing diff artifact exit" 2 #[
    "--diff",
    "LeanAssumptionsTest/Golden/does-not-exist.json",
    "LeanAssumptionsTest/Golden/delta-current.json"
  ]
  assertCliExit env opts "CLI malformed cluster artifact exit" 2 #[
    "--cluster",
    "LeanAssumptionsTest/Golden/packageBinder.txt"
  ]
  IO.FS.createDirAll ".lake/build/lean-assumptions-test"
  let unknownResultPath := ".lake/build/lean-assumptions-test/bad-result-spelling.json"
  IO.FS.writeFile unknownResultPath <|
    "{\"schema_version\":\"1\",\"lean_version\":\"x\",\"policy_identifier\":\"strict\"," ++
    "\"transparency_mode\":\"none\",\"target\":\"Example.t\",\"policy_result\":\"FAILED\"," ++
    "\"policy_findings\":[]}"
  assertCliExit env opts "CLI cluster rejects unknown result spelling" 2 #[
    "--cluster", unknownResultPath
  ]
  let futureVersionPath := ".lake/build/lean-assumptions-test/future-schema-version.json"
  IO.FS.writeFile futureVersionPath <|
    "{\"schema_version\":\"2\",\"lean_version\":\"x\",\"policy_identifier\":\"strict\"," ++
    "\"transparency_mode\":\"none\",\"target\":\"Example.t\",\"policy_result\":\"pass\"," ++
    "\"policy_findings\":[]}"
  assertCliExit env opts "CLI cluster rejects future schema version" 2 #[
    "--cluster", futureVersionPath
  ]
  assertCliExit env opts "CLI diff rejects future schema version" 2 #[
    "--diff", futureVersionPath,
    "LeanAssumptionsTest/Golden/delta-current.json"
  ]
  assertCliExit env opts "CLI help exit" 0 #["--help"]
  -- Usage-drift guard: every accepted flag must appear in the usage text.
  for flag in [
    "--module", "--decl", "--scan-module", "--format", "--policy",
    "--allow-direct", "--allow-package", "--allow-typeclasses",
    "--allow-unknowns", "--warn-unknowns", "--transparency", "--diff",
    "--cluster", "--baseline", "--accept", "--update-baseline", "--help"
  ] do
    assertTrue s!"usage documents {flag}"
      ((LeanAssumptions.Cli.usage.splitOn flag).length >= 2)
  assertCliExit env opts "CLI transparency flag expands alias" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.aliasBinder",
    "--format", "json",
    "--transparency", "reducible",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage"
  ]
  assertCliExit env opts "CLI duplicate transparency rejected" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--transparency", "reducible",
    "--transparency", "none"
  ]
  assertCliExit env opts "CLI bad transparency rejected" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--transparency", "everything"
  ]
  assertCliExit env opts "CLI delta JSON exit" 0 #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--format", "json"
  ]
  assertCliExit env opts "CLI delta text exit" 0 #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--format", "text"
  ]
  assertCliExit env opts "CLI delta rejects mixed audit options" 2 #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--format", "json"
  ]
  assertCliExit env opts "CLI cluster JSON exit" 0 #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--format", "json"
  ]
  assertCliExit env opts "CLI cluster text exit" 0 #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--format", "text"
  ]
  assertCliExit env opts "CLI cluster rejects mixed audit options" 2 #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--format", "json"
  ]
  assertCliExit env opts "CLI baseline pass exit" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--baseline", "LeanAssumptionsTest/Golden/packageBinder-batch.json"
  ]
  assertCliExit env opts "CLI baseline regression exit" 1 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--baseline", "LeanAssumptionsTest/Golden/Baseline/empty-batch.json"
  ]
  assertCliExit env opts "CLI baseline improvement exit" 0 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.noPropBearingAssumptions",
    "--baseline", "LeanAssumptionsTest/Golden/packageBinder-batch.json"
  ]
  assertCliExit env opts "CLI baseline rejects JSON output" 2 #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--baseline", "LeanAssumptionsTest/Golden/packageBinder-batch.json",
    "--format", "json"
  ]
  IO.FS.createDirAll ".lake/build/lean-assumptions-test"
  let updatePath := ".lake/build/lean-assumptions-test/baseline-update.json"
  let updateExit ← LeanAssumptions.Cli.runWithImportedEnv env opts #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--update-baseline", updatePath
  ] false
  assertEq "CLI update-baseline exit" (0 : UInt32) updateExit
  let updatedArtifact ← LeanAssumptions.Baseline.readAuditArtifact updatePath
  assertEq "CLI update-baseline writes current findings" 1 updatedArtifact.findings.size
  let acceptPath := ".lake/build/lean-assumptions-test/baseline-accept.json"
  let debtText ← IO.FS.readFile "LeanAssumptionsTest/Golden/packageBinder-batch.json"
  IO.FS.writeFile acceptPath debtText
  let acceptExit ← LeanAssumptions.Cli.runWithImportedEnv env opts #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.noPropBearingAssumptions",
    "--baseline", acceptPath,
    "--accept"
  ] false
  assertEq "CLI baseline accept exit" (0 : UInt32) acceptExit
  let acceptedArtifact ← LeanAssumptions.Baseline.readAuditArtifact acceptPath
  assertEq "CLI baseline accept updates on improvement" 0 acceptedArtifact.findings.size
