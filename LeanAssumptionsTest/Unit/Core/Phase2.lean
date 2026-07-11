import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Phase 2 unit tests for recursive package expansion, proof-carrying wrappers,
and cycle-safe unknown reporting.

Policy evaluation has separate Phase 2 tests under `Unit/Policy`.
-/

open LeanAssumptions.Core
open LeanAssumptionsTest

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  assertEq "packageBinder binder count" 1 report.binders.size
  let pkgBinder ← requireAt "packageBinder pkg binder" report.binders 0
  assertEq "packageBinder pkg category" AssumptionCategory.packageWithPropFields pkgBinder.primaryCategory
  assertEq "packageBinder direct field count" 3 pkgBinder.children.size
  let carrier ← requireAt "packageBinder carrier field" pkgBinder.children 0
  assertEq "packageBinder carrier field name" `carrier carrier.userName
  assertEq "packageBinder carrier category" AssumptionCategory.pureData carrier.primaryCategory
  let certified ← requireAt "packageBinder certified field" pkgBinder.children 1
  assertEq "packageBinder certified field name" `certified certified.userName
  assertEq "packageBinder certified category" AssumptionCategory.directProp certified.primaryCategory
  let witness ← requireAt "packageBinder witness field" pkgBinder.children 2
  assertEq "packageBinder witness field name" `witness witness.userName
  assertEq "packageBinder witness category" AssumptionCategory.directProp witness.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.classBinder
  assertEq "classBinder binder count" 3 report.binders.size
  let instBinder ← requireAt "classBinder instance binder" report.binders 1
  assertEq "classBinder instance category" AssumptionCategory.typeclassAssumption instBinder.primaryCategory
  assertEq "classBinder direct field count" 2 instBinder.children.size
  let certified ← requireAt "classBinder certified field" instBinder.children 0
  assertEq "classBinder certified field name" `certified certified.userName
  assertEq "classBinder certified category" AssumptionCategory.directProp certified.primaryCategory
  let witness ← requireAt "classBinder witness field" instBinder.children 1
  assertEq "classBinder witness field name" `witness witness.userName
  assertEq "classBinder witness category" AssumptionCategory.directProp witness.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.noPropBearingAssumptions
  assertEq "noPropBearingAssumptions binder count" 1 report.binders.size
  let binder ← requireAt "noPropBearingAssumptions binder" report.binders 0
  assertEq "noPropBearingAssumptions category" AssumptionCategory.pureData binder.primaryCategory
  assertEq "noPropBearingAssumptions field count" 0 binder.children.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.nestedPackageBinder
  assertEq "nestedPackageBinder binder count" 1 report.binders.size
  let pkgBinder ← requireAt "nestedPackageBinder pkg binder" report.binders 0
  assertEq "nestedPackageBinder pkg category" AssumptionCategory.packageWithPropFields pkgBinder.primaryCategory
  assertEq "nestedPackageBinder direct field count" 1 pkgBinder.children.size
  let inner ← requireAt "nestedPackageBinder inner field" pkgBinder.children 0
  assertEq "nestedPackageBinder inner field name" `inner inner.userName
  assertEq "nestedPackageBinder inner category" AssumptionCategory.packageWithPropFields inner.primaryCategory
  assertEq "nestedPackageBinder inner field count" 3 inner.children.size
  let certified ← requireAt "nestedPackageBinder certified nested field" inner.children 1
  assertEq "nestedPackageBinder certified category" AssumptionCategory.directProp certified.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.cyclicPackageBinder
  assertEq "cyclicPackageBinder unknowns" true report.unknownsOccurred
  assertEq "cyclicPackageBinder cycles" true report.cyclesTruncated
  let root ← requireAt "cyclicPackageBinder root binder" report.binders 0
  assertEq "cyclicPackageBinder root category" AssumptionCategory.packageWithPropFields root.primaryCategory
  let right ← requireAt "cyclicPackageBinder right field" root.children 0
  assertEq "cyclicPackageBinder right category" AssumptionCategory.packageWithPropFields right.primaryCategory
  let left ← requireAt "cyclicPackageBinder left cycle field" right.children 0
  assertEq "cyclicPackageBinder left category" AssumptionCategory.unknown left.primaryCategory
  let cycleFlag ← requireAt "cyclicPackageBinder cycle flag" left.secondaryFlags 0
  assertEq "cyclicPackageBinder cycle flag" AssumptionFlag.cycleTruncated cycleFlag

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.subtypeBinder
  let binder ← requireAt "subtypeBinder binder" report.binders 0
  assertEq "subtypeBinder category" AssumptionCategory.proofCarryingData binder.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.sigmaBinder
  let binder ← requireAt "sigmaBinder binder" report.binders 0
  assertEq "sigmaBinder category" AssumptionCategory.proofCarryingData binder.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.psigmaBinder
  let binder ← requireAt "psigmaBinder binder" report.binders 0
  assertEq "psigmaBinder category" AssumptionCategory.proofCarryingData binder.primaryCategory

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.aliasBinder
  assertEq "aliasBinder none transparency mode" TransparencyMode.none report.transparencyMode
  let binder ← requireAt "aliasBinder none binder" report.binders 0
  assertEq "aliasBinder none category" AssumptionCategory.alias binder.primaryCategory
  assertEq "aliasBinder none child count" 0 binder.children.size
  match binder.binderType.getAppFn with
  | .const name _ =>
    assertEq "aliasBinder none keeps alias head"
      `LeanAssumptionsTest.Fixtures.ProofPackageAlias name
  | _ => throwError "aliasBinder none binder type has no constant head"

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.aliasBinder
  assertEq "aliasBinder reducible transparency mode" TransparencyMode.reducible report.transparencyMode
  let binder ← requireAt "aliasBinder reducible binder" report.binders 0
  assertEq "aliasBinder reducible category" AssumptionCategory.packageWithPropFields binder.primaryCategory
  assertEq "aliasBinder reducible direct field count" 3 binder.children.size
  match binder.binderType.getAppFn with
  | .const name _ =>
    assertEq "aliasBinder reducible exposes package head"
      `LeanAssumptionsTest.Fixtures.ProofPackage name
  | _ => throwError "aliasBinder reducible binder type has no constant head"

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.recursiveNormalization `LeanAssumptionsTest.Fixtures.aliasBinder
  assertEq "aliasBinder recursive transparency mode"
    TransparencyMode.recursiveNormalization report.transparencyMode
  let binder ← requireAt "aliasBinder recursive binder" report.binders 0
  assertEq "aliasBinder recursive category" AssumptionCategory.packageWithPropFields binder.primaryCategory
  assertEq "aliasBinder recursive direct field count" 3 binder.children.size

run_cmd do
  -- The proof-validity-versus-statement-surface pair (charter TD-005): a
  -- theorem with a statement-surface assumption but an ordinary proof fails
  -- strict policy, while a theorem whose PROOF uses an axiom but whose
  -- statement takes nothing passes — proof dependencies are #print axioms'
  -- job, not this tool's.
  let surfaceReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.statementSurfaceAssumption
  let surfaceBinder ← requireAt "statementSurfaceAssumption binder" surfaceReport.binders 0
  assertEq "statementSurfaceAssumption category"
    AssumptionCategory.directProp surfaceBinder.primaryCategory
  let surfaceEvaluation := LeanAssumptions.Policy.evaluate LeanAssumptions.Policy.strictPolicy surfaceReport
  assertEq "statementSurfaceAssumption strict result"
    LeanAssumptions.Policy.PolicyResult.fail surfaceEvaluation.result
  let proofReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.proofDependsOnAxiom
  assertEq "proofDependsOnAxiom binder count" 0 proofReport.binders.size
  let proofEvaluation := LeanAssumptions.Policy.evaluate LeanAssumptions.Policy.strictPolicy proofReport
  assertEq "proofDependsOnAxiom strict result"
    LeanAssumptions.Policy.PolicyResult.pass proofEvaluation.result

run_cmd do
  -- Suspicious fixture-only declaration kinds are recovered faithfully.
  let axiomReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.suspiciousTruth
  assertEq "suspiciousTruth kind" DeclarationKind.axiom axiomReport.declarationKind
  let opaqueReport ← LeanAssumptions.Core.inspectDeclaration
    `LeanAssumptionsTest.Fixtures.suspiciousOpaque
  assertEq "suspiciousOpaque kind" DeclarationKind.opaque opaqueReport.declarationKind
