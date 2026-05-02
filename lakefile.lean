import Lake

open Lake DSL

package «lean-assumptions» where
  version := v!"0.1.0"
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
