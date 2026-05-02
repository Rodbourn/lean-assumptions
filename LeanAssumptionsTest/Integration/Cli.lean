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
