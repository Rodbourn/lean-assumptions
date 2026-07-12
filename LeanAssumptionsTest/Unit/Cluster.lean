import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for FR-018 remediation-signal classification.

The signal is inferred mechanically from public finding categories; anything
the report cannot name explicitly is conservatively hidden.
-/

open Lean Elab Command
open LeanAssumptions.Cluster
open LeanAssumptionsTest

run_cmd do
  assertEq "package-only is hidden" RemediationSignal.hidden
    (remediationSignalOfCategories #["package_with_prop_fields"])
  assertEq "proof-carrying is hidden" RemediationSignal.hidden
    (remediationSignalOfCategories #["proof_carrying_data"])
  assertEq "alias is hidden" RemediationSignal.hidden
    (remediationSignalOfCategories #["alias"])
  assertEq "unknown is hidden" RemediationSignal.hidden
    (remediationSignalOfCategories #["unknown"])
  assertEq "unrecognized category is conservatively hidden" RemediationSignal.hidden
    (remediationSignalOfCategories #["future_category"])
  assertEq "direct prop is explicit" RemediationSignal.explicitDirectProp
    (remediationSignalOfCategories #["direct_prop"])
  assertEq "typeclass is explicit" RemediationSignal.explicitTypeclass
    (remediationSignalOfCategories #["typeclass_assumption"])
  assertEq "direct plus package is mixed" RemediationSignal.mixed
    (remediationSignalOfCategories #["direct_prop", "package_with_prop_fields"])
  assertEq "direct plus typeclass is mixed" RemediationSignal.mixed
    (remediationSignalOfCategories #["direct_prop", "typeclass_assumption"])
  assertEq "repeated single bucket stays single" RemediationSignal.explicitDirectProp
    (remediationSignalOfCategories #["direct_prop", "direct_prop"])
