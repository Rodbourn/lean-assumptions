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
    `LeanAssumptionsTest.Fixtures.nestedTupleBinder
  let binder ← requireAt "nestedTupleBinder binder" report.binders 0
  assertEq "nestedTupleBinder category" AssumptionCategory.pureData binder.primaryCategory
  assertEq "nestedTupleBinder cycles" false report.cyclesTruncated
  assertEq "nestedTupleBinder unknowns" false report.unknownsOccurred
  assertEq "nestedTupleBinder child count" 2 binder.children.size
  let snd ← requireAt "nestedTupleBinder snd field" binder.children 1
  assertEq "nestedTupleBinder snd category" AssumptionCategory.pureData snd.primaryCategory
  assertEq "nestedTupleBinder snd child count" 2 snd.children.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.pairOfPackagesBinder
  let binder ← requireAt "pairOfPackagesBinder binder" report.binders 0
  assertEq "pairOfPackagesBinder category"
    AssumptionCategory.packageWithPropFields binder.primaryCategory
  assertEq "pairOfPackagesBinder cycles" false report.cyclesTruncated
  let fst ← requireAt "pairOfPackagesBinder fst field" binder.children 0
  assertEq "pairOfPackagesBinder fst category"
    AssumptionCategory.packageWithPropFields fst.primaryCategory

run_cmd do
  -- Fuel exhaustion is a conservative-failure branch: expansion beyond the
  -- fuel bound must surface as unknown, never as a silently truncated pass.
  let report ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.deepTupleBinder
  assertEq "deepTupleBinder unknowns" true report.unknownsOccurred
  let evaluation := Policy.evaluate
    { Policy.strictPolicy with transparencyMode := .reducible } report
  assertEq "deepTupleBinder strict result" PolicyResult.fail evaluation.result

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.aliasHiddenStatement
  assertEq "aliasHiddenStatement binder count" 0 report.binders.size
  match report.resultSurface? with
  | some node =>
    assertEq "aliasHiddenStatement result surface category"
      AssumptionCategory.alias node.primaryCategory
    assertEq "aliasHiddenStatement result surface name" `result node.userName
  | none => throwError "aliasHiddenStatement expected a blocked result surface"

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.defHiddenStatement
  assertEq "defHiddenStatement binder count" 0 report.binders.size
  match report.resultSurface? with
  | some node =>
    assertEq "defHiddenStatement result surface category"
      AssumptionCategory.alias node.primaryCategory
  | none => throwError "defHiddenStatement expected a blocked result surface"

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.aliasHiddenStatement
  assertEq "aliasHiddenStatement reducible binder count" 1 report.binders.size
  let binder ← requireAt "aliasHiddenStatement reducible binder" report.binders 0
  assertEq "aliasHiddenStatement reducible binder category"
    AssumptionCategory.directProp binder.primaryCategory
  match report.resultSurface? with
  | some _ => throwError "aliasHiddenStatement reducible expected a fully peeled result"
  | none => pure ()

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.packageBinder
  match report.resultSurface? with
  | some _ => throwError "packageBinder expected no blocked result surface"
  | none => pure ()

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.aliasHiddenStatement
  let evaluation := Policy.evaluate Policy.strictPolicy report
  assertEq "aliasHiddenStatement strict result" PolicyResult.fail evaluation.result
  let finding ← requireAt "aliasHiddenStatement strict finding" evaluation.findings 0
  assertEq "aliasHiddenStatement finding kind"
    PolicyFindingKind.unsupportedAlias finding.kind
  let pathHead ← requireAt "aliasHiddenStatement finding path" finding.path 0
  assertEq "aliasHiddenStatement finding path head" `result pathHead

run_cmd do
  -- Under `reducible` transparency, a plain-def alias stays folded and is
  -- reported as an alias, while a reducible-attribute alias unfolds; under
  -- `recursive_normalization` both unfold. This pins the three modes as
  -- operationally distinct.
  let plainReducible ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.defAliasPackageBinder
  let plainBinder ← requireAt "defAliasPackageBinder reducible binder" plainReducible.binders 0
  assertEq "defAliasPackageBinder reducible category"
    AssumptionCategory.alias plainBinder.primaryCategory
  assertEq "defAliasPackageBinder reducible transparency-limited"
    true plainReducible.transparencyLimited
  let attrReducible ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.reducibleDefAliasPackageBinder
  let attrBinder ← requireAt "reducibleDefAliasPackageBinder reducible binder" attrReducible.binders 0
  assertEq "reducibleDefAliasPackageBinder reducible category"
    AssumptionCategory.packageWithPropFields attrBinder.primaryCategory
  assertEq "reducibleDefAliasPackageBinder reducible transparency-limited"
    false attrReducible.transparencyLimited
  let plainRecursive ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.recursiveNormalization `LeanAssumptionsTest.Fixtures.defAliasPackageBinder
  let recursiveBinder ← requireAt "defAliasPackageBinder recursive binder" plainRecursive.binders 0
  assertEq "defAliasPackageBinder recursive category"
    AssumptionCategory.packageWithPropFields recursiveBinder.primaryCategory
  assertEq "defAliasPackageBinder recursive transparency-limited"
    false plainRecursive.transparencyLimited

run_cmd do
  let aliasReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.aliasBinder
  assertEq "aliasBinder none transparency-limited" true aliasReport.transparencyLimited
  let dataReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.noPropBearingAssumptions
  assertEq "noPropBearingAssumptions transparency-limited"
    false dataReport.transparencyLimited

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
  assertStrictResult "defHiddenStatement strict result"
    `LeanAssumptionsTest.Fixtures.defHiddenStatement PolicyResult.fail
  assertStrictResult "nestedTupleBinder strict result"
    `LeanAssumptionsTest.Fixtures.nestedTupleBinder PolicyResult.pass
  assertStrictResult "pairOfPackagesBinder strict result"
    `LeanAssumptionsTest.Fixtures.pairOfPackagesBinder PolicyResult.fail
  assertStrictResult "functionIntoDataBinder strict result"
    `LeanAssumptionsTest.Fixtures.functionIntoDataBinder PolicyResult.pass
  assertStrictResult "listDataBinder strict result"
    `LeanAssumptionsTest.Fixtures.listDataBinder PolicyResult.pass
