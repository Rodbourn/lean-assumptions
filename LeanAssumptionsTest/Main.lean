import LeanAssumptionsTest.Unit.Core.Phase1
import LeanAssumptionsTest.Unit.Core.Phase2
import LeanAssumptionsTest.Unit.Core.Adversarial
import LeanAssumptionsTest.Unit.Policy.Phase2
import LeanAssumptionsTest.Unit.Policy.Digest
import LeanAssumptionsTest.Unit.Policy.Budget
import LeanAssumptionsTest.Unit.PolicyFile
import LeanAssumptionsTest.Unit.Render
import LeanAssumptionsTest.Unit.Baseline.Phase4
import LeanAssumptionsTest.Integration.Phase1
import LeanAssumptionsTest.Golden.Phase3
import LeanAssumptionsTest.Golden.Delta
import LeanAssumptionsTest.Golden.Cluster
import LeanAssumptionsTest.Golden.Baseline
import LeanAssumptionsTest.Integration.Commands
import LeanAssumptionsTest.Integration.Cli
import LeanAssumptionsTest.Coverage
import LeanAssumptionsTest.GoldenRuntime
import LeanAssumptionsTest.Property.Soundness

/-!
Test executable root for `lean-assumptions`.

The imported modules contain compile-time assertions via `run_cmd`. The
runtime entry point then re-runs every golden comparison, because
elaboration-time comparisons are skipped by build caching when only a golden
file changed.
-/

/-- Re-verify goldens at runtime, then confirm the compile-time assertions. -/
def main : IO UInt32 := do
  let failures ← LeanAssumptionsTest.GoldenRuntime.goldenFailures
  if failures.isEmpty then
    IO.println "lean-assumptions tests passed"
    pure 0
  else
    for failure in failures do
      IO.eprintln s!"golden mismatch: {failure}"
    pure 1
