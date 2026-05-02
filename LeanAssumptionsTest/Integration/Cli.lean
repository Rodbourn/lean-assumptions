import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Integration tests for the Phase 3 CLI support API.

The Lake executable is a thin wrapper around `LeanAssumptions.Cli.run`; these
tests exercise argument parsing, module imports, declaration lists, module
scans, policy files, output modes, and policy exit codes.
-/

open LeanAssumptionsTest

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json"
  ]
  assertEq "CLI strict package failure exit" 1 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage"
  ]
  assertEq "CLI allowlisted package exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "text",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-allow-package.json"
  ]
  assertEq "CLI policy file exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.noPropBearingAssumptions",
    "--decl", "LeanAssumptionsTest.Fixtures.packageBinder",
    "--format", "json",
    "--allow-package", "LeanAssumptionsTest.Fixtures.ProofPackage"
  ]
  assertEq "CLI declaration list exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures.Phase1",
    "--scan-module", "LeanAssumptionsTest.Fixtures.Phase1",
    "--format", "json"
  ]
  assertEq "CLI module scan strict exit" 1 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--module", "LeanAssumptionsTest.Fixtures",
    "--decl", "LeanAssumptionsTest.Fixtures.aliasBinder",
    "--format", "json",
    "--policy", "LeanAssumptionsTest/Fixtures/policy-reducible-allow-package.json"
  ]
  assertEq "CLI reducible alias policy exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--format", "json"
  ]
  assertEq "CLI delta JSON exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--format", "text"
  ]
  assertEq "CLI delta text exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--diff",
    "LeanAssumptionsTest/Golden/delta-baseline.json",
    "LeanAssumptionsTest/Golden/delta-current.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--format", "json"
  ]
  assertEq "CLI delta rejects mixed audit options" 2 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--format", "json"
  ]
  assertEq "CLI cluster JSON exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--format", "text"
  ]
  assertEq "CLI cluster text exit" 0 code

run_cmd do
  let code ← LeanAssumptions.Cli.run #[
    "--cluster",
    "LeanAssumptionsTest/Golden/cluster-input.json",
    "--module", "LeanAssumptionsTest.Fixtures",
    "--format", "json"
  ]
  assertEq "CLI cluster rejects mixed audit options" 2 code
