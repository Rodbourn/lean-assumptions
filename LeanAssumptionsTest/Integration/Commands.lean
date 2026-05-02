import LeanAssumptions
import LeanAssumptionsTest.Fixtures

/-!
Integration tests for the public Phase 3 `#print` command surface.

The renderer has separate golden tests; this file verifies that the command
adapters elaborate against real fixture declarations.
-/

#print assumptions LeanAssumptionsTest.Fixtures.packageBinder

#print assumption_tree LeanAssumptionsTest.Fixtures.packageBinder

#print assumption_json LeanAssumptionsTest.Fixtures.packageBinder
