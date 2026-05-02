import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Phase 1 end-to-end tests through the public package surface.
-/

open LeanAssumptions.Core
open LeanAssumptionsTest

run_cmd do
  assertEq "toolVersion" "0.1.0-dev" LeanAssumptions.toolVersion
  assertEq "reportModelVersion" "0.1.0-dev" LeanAssumptions.reportModelVersion

run_cmd do
  let report ← LeanAssumptions.inspectDeclaration `LeanAssumptionsTest.Fixtures.implicitProp
  assertEq "implicitProp transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "implicitProp unknowns flag" false report.unknownsOccurred
  assertEq "implicitProp cycles flag" false report.cyclesTruncated
  assertEq "implicitProp binder count" 2 report.binders.size
  let pBinder ← requireAt "implicitProp p binder" report.binders 0
  assertEq "implicitProp p binder name" `p pBinder.userName
  assertEq "implicitProp p binder kind" SurfaceBinderKind.implicit pBinder.binderKind
  assertEq "implicitProp p category" AssumptionCategory.directProp pBinder.primaryCategory
  assertEq "implicitProp p flag count" 1 pBinder.secondaryFlags.size
  let hBinder ← requireAt "implicitProp h binder" report.binders 1
  assertEq "implicitProp h binder name" `h hBinder.userName
  assertEq "implicitProp h binder kind" SurfaceBinderKind.implicit hBinder.binderKind
  assertEq "implicitProp h category" AssumptionCategory.directProp hBinder.primaryCategory
  assertEq "implicitProp h flag count" 1 hBinder.secondaryFlags.size

run_cmd do
  let report ← LeanAssumptions.inspectDeclaration `LeanAssumptionsTest.Fixtures.strictImplicitProp
  assertEq "strictImplicitProp transparency mode" TransparencyMode.none report.transparencyMode
  assertEq "strictImplicitProp unknowns flag" false report.unknownsOccurred
  assertEq "strictImplicitProp cycles flag" false report.cyclesTruncated
  assertEq "strictImplicitProp binder count" 2 report.binders.size
  let pBinder ← requireAt "strictImplicitProp p binder" report.binders 0
  assertEq "strictImplicitProp p binder name" `p pBinder.userName
  assertEq "strictImplicitProp p binder kind" SurfaceBinderKind.strictImplicit pBinder.binderKind
  assertEq "strictImplicitProp p category" AssumptionCategory.directProp pBinder.primaryCategory
  let hBinder ← requireAt "strictImplicitProp h binder" report.binders 1
  assertEq "strictImplicitProp h binder name" `h hBinder.userName
  assertEq "strictImplicitProp h binder kind" SurfaceBinderKind.strictImplicit hBinder.binderKind
  assertEq "strictImplicitProp h category" AssumptionCategory.directProp hBinder.primaryCategory
