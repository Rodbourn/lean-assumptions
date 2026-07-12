import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Phase 1 unit tests for the trusted-core core.

These tests are added before the inspection implementation is written. They
define the required behavior for declaration lookup, binder peeling, binder-kind
classification, and direct proposition detection.
-/

open LeanAssumptions.Core
open LeanAssumptionsTest

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.explicitProp
  assertEq "explicitProp name" `LeanAssumptionsTest.Fixtures.explicitProp report.declarationName
  assertEq "explicitProp kind" DeclarationKind.theorem report.declarationKind
  assertTrue "explicitProp declaration type is a forall" report.declarationType.isForall
  assertEq "explicitProp transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "explicitProp unknowns flag" false report.unknownsOccurred
  assertEq "explicitProp cycles flag" false report.cyclesTruncated
  assertEq "explicitProp binder count" 2 report.binders.size
  let pBinder ← requireAt "explicitProp p binder" report.binders 0
  assertEq "explicitProp p binder name" `p pBinder.userName
  assertEq "explicitProp p binder kind" SurfaceBinderKind.explicit pBinder.binderKind
  assertEq "explicitProp p category" AssumptionCategory.directProp pBinder.primaryCategory
  assertEq "explicitProp p flag count" 1 pBinder.secondaryFlags.size
  let pFlag ← requireAt "explicitProp p flag" pBinder.secondaryFlags 0
  assertEq "explicitProp p direct-prop flag" AssumptionFlag.binderQuantifiesOverProp pFlag
  let hBinder ← requireAt "explicitProp h binder" report.binders 1
  assertEq "explicitProp h binder name" `h hBinder.userName
  assertEq "explicitProp h binder kind" SurfaceBinderKind.explicit hBinder.binderKind
  assertEq "explicitProp h category" AssumptionCategory.directProp hBinder.primaryCategory
  assertEq "explicitProp h flag count" 1 hBinder.secondaryFlags.size
  let hFlag ← requireAt "explicitProp h flag" hBinder.secondaryFlags 0
  assertEq "explicitProp h direct-prop flag" AssumptionFlag.binderTypeIsProp hFlag
  assertTrue "explicitProp result type retained" report.resultType.isFVar

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.hypothesisBinder
  assertEq "hypothesisBinder binder count" 2 report.binders.size
  let pBinder ← requireAt "hypothesisBinder P binder" report.binders 0
  assertEq "hypothesisBinder P category" AssumptionCategory.directProp pBinder.primaryCategory
  assertEq "hypothesisBinder P flag count" 1 pBinder.secondaryFlags.size
  let pFlag ← requireAt "hypothesisBinder P flag" pBinder.secondaryFlags 0
  assertEq "hypothesisBinder P quantifier flag" AssumptionFlag.binderQuantifiesOverProp pFlag
  let hBinder ← requireAt "hypothesisBinder h binder" report.binders 1
  assertEq "hypothesisBinder h category" AssumptionCategory.directProp hBinder.primaryCategory
  assertEq "hypothesisBinder h flag count" 1 hBinder.secondaryFlags.size
  let hFlag ← requireAt "hypothesisBinder h flag" hBinder.secondaryFlags 0
  assertEq "hypothesisBinder h proof flag" AssumptionFlag.binderTypeIsProp hFlag

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.quantifierOverProp
  assertEq "quantifierOverProp binder count" 1 report.binders.size
  let pBinder ← requireAt "quantifierOverProp P binder" report.binders 0
  assertEq "quantifierOverProp P category" AssumptionCategory.directProp pBinder.primaryCategory
  assertEq "quantifierOverProp P flag count" 1 pBinder.secondaryFlags.size
  let pFlag ← requireAt "quantifierOverProp P flag" pBinder.secondaryFlags 0
  assertEq "quantifierOverProp P quantifier flag" AssumptionFlag.binderQuantifiesOverProp pFlag

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.allBinderKinds
  assertEq "allBinderKinds transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "allBinderKinds unknowns flag" false report.unknownsOccurred
  assertEq "allBinderKinds cycles flag" false report.cyclesTruncated
  assertEq "allBinderKinds binder count" 5 report.binders.size
  let αBinder ← requireAt "allBinderKinds α binder" report.binders 0
  assertEq "allBinderKinds α binder name" `α αBinder.userName
  assertEq "allBinderKinds α binder kind" SurfaceBinderKind.implicit αBinder.binderKind
  assertEq "allBinderKinds α category" AssumptionCategory.pureData αBinder.primaryCategory
  assertEq "allBinderKinds α flags" 0 αBinder.secondaryFlags.size
  let pBinder ← requireAt "allBinderKinds p binder" report.binders 1
  assertEq "allBinderKinds p binder name" `p pBinder.userName
  assertEq "allBinderKinds p binder kind" SurfaceBinderKind.strictImplicit pBinder.binderKind
  assertEq "allBinderKinds p category" AssumptionCategory.directProp pBinder.primaryCategory
  assertEq "allBinderKinds p flag count" 1 pBinder.secondaryFlags.size
  let pFlag ← requireAt "allBinderKinds p flag" pBinder.secondaryFlags 0
  assertEq "allBinderKinds p flag" AssumptionFlag.binderQuantifiesOverProp pFlag
  let instBinder ← requireAt "allBinderKinds inst binder" report.binders 2
  assertEq "allBinderKinds inst binder name" `inst instBinder.userName
  assertEq "allBinderKinds inst binder kind" SurfaceBinderKind.instanceImplicit instBinder.binderKind
  assertEq "allBinderKinds inst category" AssumptionCategory.typeclassAssumption instBinder.primaryCategory
  assertEq "allBinderKinds inst flag count" 1 instBinder.secondaryFlags.size
  let instFlag ← requireAt "allBinderKinds inst flag" instBinder.secondaryFlags 0
  assertEq "allBinderKinds inst flag" AssumptionFlag.instanceBinder instFlag
  let xBinder ← requireAt "allBinderKinds x binder" report.binders 3
  assertEq "allBinderKinds x binder name" `x xBinder.userName
  assertEq "allBinderKinds x binder kind" SurfaceBinderKind.explicit xBinder.binderKind
  assertEq "allBinderKinds x category" AssumptionCategory.pureData xBinder.primaryCategory
  assertEq "allBinderKinds x flags" 0 xBinder.secondaryFlags.size
  let hBinder ← requireAt "allBinderKinds h binder" report.binders 4
  assertEq "allBinderKinds h binder name" `h hBinder.userName
  assertEq "allBinderKinds h binder kind" SurfaceBinderKind.explicit hBinder.binderKind
  assertEq "allBinderKinds h category" AssumptionCategory.directProp hBinder.primaryCategory
  assertEq "allBinderKinds h flag count" 1 hBinder.secondaryFlags.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.pureDataOnly
  assertEq "pureDataOnly kind" DeclarationKind.theorem report.declarationKind
  assertEq "pureDataOnly transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "pureDataOnly unknowns flag" false report.unknownsOccurred
  assertEq "pureDataOnly cycles flag" false report.cyclesTruncated
  assertEq "pureDataOnly binder count" 1 report.binders.size
  let binder ← requireAt "pureDataOnly binder" report.binders 0
  assertEq "pureDataOnly binder category" AssumptionCategory.pureData binder.primaryCategory
  assertEq "pureDataOnly binder flags" 0 binder.secondaryFlags.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.plainDefinition
  assertEq "plainDefinition kind" DeclarationKind.definition report.declarationKind
  assertEq "plainDefinition transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "plainDefinition unknowns flag" false report.unknownsOccurred
  assertEq "plainDefinition cycles flag" false report.cyclesTruncated
