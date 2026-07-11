import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Regression tests for the 2026-07-11 audit: statement shapes that previously
misclassified as `pure_data` and passed strict policy must now classify
conservatively, and plain-data shapes must keep passing.
-/

open LeanAssumptions
open LeanAssumptions.Core
open LeanAssumptions.Policy
open LeanAssumptionsTest

/-- Assert that strict policy evaluation of a declaration yields a result. -/
private def assertStrictResult (label : String) (declName : Lean.Name)
    (expected : PolicyResult) : Lean.Elab.Command.CommandElabM Unit := do
  let report ← LeanAssumptions.Core.inspectDeclaration declName
  let evaluation := Policy.evaluate Policy.strictPolicy report
  assertEq label expected evaluation.result

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.letWrappedPackageBinder
  assertEq "letWrappedPackageBinder binder count" 1 report.binders.size
  let binder ← requireAt "letWrappedPackageBinder binder" report.binders 0
  assertEq "letWrappedPackageBinder category"
    AssumptionCategory.packageWithPropFields binder.primaryCategory
  assertEq "letWrappedPackageBinder field count" 3 binder.children.size
  assertEq "letWrappedPackageBinder unknowns" false report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.inductiveProofCarrierBinder
  let binder ← requireAt "inductiveProofCarrierBinder binder" report.binders 0
  assertEq "inductiveProofCarrierBinder category"
    AssumptionCategory.proofCarryingData binder.primaryCategory
  assertEq "inductiveProofCarrierBinder child count" 1 binder.children.size
  let child ← requireAt "inductiveProofCarrierBinder proof field" binder.children 0
  assertEq "inductiveProofCarrierBinder proof field name" `intro.h child.userName
  assertEq "inductiveProofCarrierBinder proof field category"
    AssumptionCategory.directProp child.primaryCategory
  assertEq "inductiveProofCarrierBinder unknowns" false report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.functionIntoSubtypeBinder
  let binder ← requireAt "functionIntoSubtypeBinder binder" report.binders 0
  assertEq "functionIntoSubtypeBinder category"
    AssumptionCategory.proofCarryingData binder.primaryCategory
  assertEq "functionIntoSubtypeBinder child count" 1 binder.children.size
  let child ← requireAt "functionIntoSubtypeBinder codomain" binder.children 0
  assertEq "functionIntoSubtypeBinder codomain name" `codomain child.userName
  assertEq "functionIntoSubtypeBinder codomain category"
    AssumptionCategory.proofCarryingData child.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.functionIntoDataBinder
  let binder ← requireAt "functionIntoDataBinder binder" report.binders 0
  assertEq "functionIntoDataBinder category"
    AssumptionCategory.pureData binder.primaryCategory
  assertEq "functionIntoDataBinder child count" 0 binder.children.size
  assertEq "functionIntoDataBinder unknowns" false report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.listDataBinder
  let binder ← requireAt "listDataBinder binder" report.binders 0
  assertEq "listDataBinder category" AssumptionCategory.pureData binder.primaryCategory
  assertEq "listDataBinder child count" 0 binder.children.size
  assertEq "listDataBinder unknowns" false report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.listOfProofCarriersBinder
  let binder ← requireAt "listOfProofCarriersBinder binder" report.binders 0
  assertEq "listOfProofCarriersBinder category"
    AssumptionCategory.proofCarryingData binder.primaryCategory
  assertEq "listOfProofCarriersBinder child count" 1 binder.children.size
  let child ← requireAt "listOfProofCarriersBinder element field" binder.children 0
  assertEq "listOfProofCarriersBinder element field category"
    AssumptionCategory.proofCarryingData child.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.aliasFieldPackageBinder
  let binder ← requireAt "aliasFieldPackageBinder binder" report.binders 0
  assertEq "aliasFieldPackageBinder category"
    AssumptionCategory.unknown binder.primaryCategory
  assertEq "aliasFieldPackageBinder child count" 1 binder.children.size
  let child ← requireAt "aliasFieldPackageBinder inner field" binder.children 0
  assertEq "aliasFieldPackageBinder inner field name" `inner child.userName
  assertEq "aliasFieldPackageBinder inner field category"
    AssumptionCategory.alias child.primaryCategory
  assertEq "aliasFieldPackageBinder unknowns" true report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.opaqueHeadBinder
  let binder ← requireAt "opaqueHeadBinder binder" report.binders 0
  assertEq "opaqueHeadBinder category" AssumptionCategory.unknown binder.primaryCategory
  assertEq "opaqueHeadBinder unknowns" true report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.defAliasPackageBinder
  let binder ← requireAt "defAliasPackageBinder binder" report.binders 0
  assertEq "defAliasPackageBinder category"
    AssumptionCategory.alias binder.primaryCategory
  assertEq "defAliasPackageBinder unknowns" false report.unknownsOccurred
  match binder.binderType.getAppFn with
  | .const name _ =>
    assertEq "defAliasPackageBinder keeps alias head"
      `LeanAssumptionsTest.Fixtures.PlainDefPackageAlias name
  | _ => throwError "defAliasPackageBinder binder type has no constant head"

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.reducibleDefAliasPackageBinder
  let binder ← requireAt "reducibleDefAliasPackageBinder binder" report.binders 0
  assertEq "reducibleDefAliasPackageBinder category"
    AssumptionCategory.alias binder.primaryCategory
  assertEq "reducibleDefAliasPackageBinder unknowns" false report.unknownsOccurred

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.propAliasBinder
  let binder ← requireAt "propAliasBinder binder" report.binders 0
  assertEq "propAliasBinder category"
    AssumptionCategory.directProp binder.primaryCategory
  let flag ← requireAt "propAliasBinder flag" binder.secondaryFlags 0
  assertEq "propAliasBinder proof flag" AssumptionFlag.binderTypeIsProp flag

run_cmd do
  assertStrictResult "letWrappedPackageBinder strict result"
    `LeanAssumptionsTest.Fixtures.letWrappedPackageBinder PolicyResult.fail
  assertStrictResult "inductiveProofCarrierBinder strict result"
    `LeanAssumptionsTest.Fixtures.inductiveProofCarrierBinder PolicyResult.fail
  assertStrictResult "functionIntoSubtypeBinder strict result"
    `LeanAssumptionsTest.Fixtures.functionIntoSubtypeBinder PolicyResult.fail
  assertStrictResult "listOfProofCarriersBinder strict result"
    `LeanAssumptionsTest.Fixtures.listOfProofCarriersBinder PolicyResult.fail
  assertStrictResult "aliasFieldPackageBinder strict result"
    `LeanAssumptionsTest.Fixtures.aliasFieldPackageBinder PolicyResult.fail
  assertStrictResult "opaqueHeadBinder strict result"
    `LeanAssumptionsTest.Fixtures.opaqueHeadBinder PolicyResult.fail
  assertStrictResult "defAliasPackageBinder strict result"
    `LeanAssumptionsTest.Fixtures.defAliasPackageBinder PolicyResult.fail
  assertStrictResult "reducibleDefAliasPackageBinder strict result"
    `LeanAssumptionsTest.Fixtures.reducibleDefAliasPackageBinder PolicyResult.fail
  assertStrictResult "propAliasBinder strict result"
    `LeanAssumptionsTest.Fixtures.propAliasBinder PolicyResult.fail
  assertStrictResult "functionIntoDataBinder strict result"
    `LeanAssumptionsTest.Fixtures.functionIntoDataBinder PolicyResult.pass
  assertStrictResult "listDataBinder strict result"
    `LeanAssumptionsTest.Fixtures.listDataBinder PolicyResult.pass
