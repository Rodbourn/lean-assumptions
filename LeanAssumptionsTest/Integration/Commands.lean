import LeanAssumptions
import LeanAssumptionsTest.Fixtures

/-!
Integration tests for the public `#assumptions` command surface.

The renderer has separate golden tests; this file verifies that the command
adapters elaborate against real fixture declarations in both the default
hidden-surface mode and the explicit strict mode.
-/

#assumptions LeanAssumptionsTest.Fixtures.packageBinder

#assumptions strict LeanAssumptionsTest.Fixtures.packageBinder

#assumptions_json LeanAssumptionsTest.Fixtures.packageBinder

#assumptions_json strict LeanAssumptionsTest.Fixtures.packageBinder
