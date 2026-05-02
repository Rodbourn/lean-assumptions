import LeanAssumptions
import LeanAssumptionsTest.Fixtures
import LeanAssumptionsTest.TestUtil

/-!
Phase 2 unit tests for deterministic strict policy evaluation.

These tests are written before the policy implementation. They specify the
minimum certified policy behavior required by the charter for Phase 2.
-/

open LeanAssumptions
open LeanAssumptions.Core
open LeanAssumptions.Policy
open LeanAssumptionsTest

private def hasFindingKind (evaluation : PolicyEvaluation) (kind : PolicyFindingKind) : Bool :=
  evaluation.findings.any (fun finding => finding.kind == kind)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.explicitProp
  let evaluation := evaluate strictPolicy report
  assertEq "strict direct proposition result" PolicyResult.fail evaluation.result
  assertTrue "strict direct proposition finding"
    (hasFindingKind evaluation PolicyFindingKind.unapprovedDirectProp)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.explicitProp
  let policy := {
    strictPolicy with
    permittedDirectProps := #[
      NamePattern.exact `p,
      NamePattern.exact `h
    ]
  }
  let evaluation := evaluate policy report
  assertEq "permitted direct propositions result" PolicyResult.pass evaluation.result
  assertEq "permitted direct propositions findings" 0 evaluation.findings.size
  assertTrue "prefix name pattern matches explicitly"
    ((NamePattern.prefix `LeanAssumptionsTest.Fixtures).matches
      `LeanAssumptionsTest.Fixtures.ProofPackage)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  let evaluation := evaluate strictPolicy report
  assertEq "strict package result" PolicyResult.fail evaluation.result
  assertTrue "strict package finding"
    (hasFindingKind evaluation PolicyFindingKind.unapprovedPackageWithPropFields)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.packageBinder
  let policy := {
    strictPolicy with
    permittedPackageTypes := #[
      NamePattern.exact `LeanAssumptionsTest.Fixtures.ProofPackage
    ]
  }
  let evaluation := evaluate policy report
  assertEq "permitted package result" PolicyResult.pass evaluation.result
  assertEq "permitted package findings" 0 evaluation.findings.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.subtypeBinder
  let evaluation := evaluate strictPolicy report
  assertEq "strict proof-carrying result" PolicyResult.fail evaluation.result
  assertTrue "strict proof-carrying finding"
    (hasFindingKind evaluation PolicyFindingKind.unapprovedProofCarryingData)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.subtypeBinder
  let policy := {
    strictPolicy with
    permittedPackageTypes := #[NamePattern.exact `Subtype]
  }
  let evaluation := evaluate policy report
  assertEq "permitted proof-carrying result" PolicyResult.pass evaluation.result
  assertEq "permitted proof-carrying findings" 0 evaluation.findings.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.classBinder
  let evaluation := evaluate strictPolicy report
  assertEq "strict typeclass result" PolicyResult.fail evaluation.result
  assertTrue "strict typeclass finding"
    (hasFindingKind evaluation PolicyFindingKind.unapprovedTypeclassAssumption)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.classBinder
  let policy := { strictPolicy with typeclassPolicy := AssumptionTreatment.allow }
  let evaluation := evaluate policy report
  assertEq "allowed typeclass result" PolicyResult.pass evaluation.result
  assertEq "allowed typeclass findings" 0 evaluation.findings.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.classBinder
  let policy := { strictPolicy with typeclassPolicy := AssumptionTreatment.warn }
  let evaluation := evaluate policy report
  assertEq "warned typeclass result" PolicyResult.warn evaluation.result
  assertTrue "warned typeclass finding"
    (hasFindingKind evaluation PolicyFindingKind.unapprovedTypeclassAssumption)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.pureDataOnly
  let binder ← requireAt "synthetic unknown binder" report.binders 0
  let unknownReport := {
    report with
    binders := #[{ binder with primaryCategory := AssumptionCategory.unknown }]
    unknownsOccurred := true
  }
  let warnEvaluation := evaluate { strictPolicy with unknownPolicy := AssumptionTreatment.warn } unknownReport
  assertEq "warned unknown result" PolicyResult.warn warnEvaluation.result
  let allowEvaluation := evaluate { strictPolicy with unknownPolicy := AssumptionTreatment.allow } unknownReport
  assertEq "allowed unknown result" PolicyResult.pass allowEvaluation.result

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.cyclicPackageBinder
  let evaluation := evaluate strictPolicy report
  assertEq "strict cycle result" PolicyResult.fail evaluation.result
  assertTrue "strict cycle unknown finding"
    (hasFindingKind evaluation PolicyFindingKind.unknownNode)
  assertTrue "strict cycle truncation finding"
    (hasFindingKind evaluation PolicyFindingKind.cycleTruncated)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.pureDataOnly
  let policy := { strictPolicy with transparencyMode := TransparencyMode.reducible }
  let evaluation := evaluate policy report
  assertEq "transparency mismatch result" PolicyResult.auditError evaluation.result
  assertTrue "transparency mismatch finding"
    (hasFindingKind evaluation PolicyFindingKind.transparencyMismatch)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.aliasBinder
  let evaluation := evaluate strictPolicy report
  assertEq "strict alias result" PolicyResult.fail evaluation.result
  assertTrue "strict alias finding"
    (hasFindingKind evaluation PolicyFindingKind.unsupportedAlias)

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclaration `LeanAssumptionsTest.Fixtures.aliasBinder
  let policy := { strictPolicy with aliasPolicy := AssumptionTreatment.allow }
  let evaluation := evaluate policy report
  assertEq "allowed alias result" PolicyResult.pass evaluation.result
  assertEq "allowed alias findings" 0 evaluation.findings.size

run_cmd do
  let report ← LeanAssumptions.Core.inspectDeclarationWithTransparency
    TransparencyMode.reducible `LeanAssumptionsTest.Fixtures.aliasBinder
  let policy := {
    strictPolicy with
    transparencyMode := TransparencyMode.reducible
    permittedPackageTypes := #[NamePattern.exact `LeanAssumptionsTest.Fixtures.ProofPackage]
  }
  let evaluation := evaluate policy report
  assertEq "reducible alias package allowlist result" PolicyResult.pass evaluation.result
  assertEq "reducible alias package allowlist findings" 0 evaluation.findings.size
