import LeanAssumptionsTest.Unit.Core.Phase1
import LeanAssumptionsTest.Unit.Core.Phase2
import LeanAssumptionsTest.Unit.Policy.Phase2
import LeanAssumptionsTest.Unit.Render
import LeanAssumptionsTest.Unit.Baseline.Phase4
import LeanAssumptionsTest.Integration.Phase1
import LeanAssumptionsTest.Golden.Phase3
import LeanAssumptionsTest.Golden.Delta
import LeanAssumptionsTest.Golden.Cluster
import LeanAssumptionsTest.Golden.Baseline
import LeanAssumptionsTest.Integration.Commands
import LeanAssumptionsTest.Integration.Cli

/-!
Test executable root for `lean-assumptions`.

The imported modules contain compile-time assertions via `run_cmd`. If those
assertions hold, this executable becomes a trivial runtime confirmation target.
-/

/-- Runtime confirmation entry point once compile-time test modules succeed. -/
def main : IO Unit := IO.println "lean-assumptions tests passed"
