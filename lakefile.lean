import Lake

open Lake DSL

package «lean-assumptions» where
  version := v!"0.2.1"
  description := "Audit assumption surfaces in elaborated Lean declaration types."
  keywords := #["lean", "assumptions", "audit", "static-analysis"]
  license := "Apache-2.0"
  reservoir := true

@[default_target]
lean_lib LeanAssumptions where

lean_lib LeanAssumptionsTest where

@[test_driver]
lean_exe «lean-assumptions-test» where
  root := `LeanAssumptionsTest.Main

lean_exe «lean-assumptions» where
  root := `LeanAssumptions.Cli.Main

/--
Lint the current repository surface by building the package and test target
with Lean warnings promoted to failures.
-/
@[lint_driver]
script lint (_args) do
  let child ← IO.Process.spawn {
    cmd := "lake"
    args := #["--wfail", "build", "LeanAssumptions", "LeanAssumptionsTest", "lean-assumptions-test",
      "lean-assumptions"]
  }
  return ← child.wait
