import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Unit tests for policy digests and CLI policy-modifier composition.

The digest must identify policy semantics independently of the identifier
label, and CLI modifiers must compose deterministically with a truthful
identifier regardless of argument order.
-/

open LeanAssumptions
open LeanAssumptions.Policy
open LeanAssumptionsTest

run_cmd do
  let strict := Policy.strictPolicy
  assertEq "digest deterministic" strict.digest strict.digest
  assertTrue "digest has fnv1a64 shape" (strict.digest.startsWith "fnv1a64:")
  assertEq "digest length" 24 strict.digest.length
  let relabeled := { strict with identifier := "renamed" }
  assertEq "digest ignores identifier label" strict.digest relabeled.digest
  let weakened := { strict with permittedPackageTypes := #[.exact `Some.Package] }
  assertTrue "digest distinguishes semantics" (strict.digest != weakened.digest)
  let orderA := { strict with permittedPackageTypes := #[.exact `A, .prefix `B] }
  let orderB := { strict with permittedPackageTypes := #[.prefix `B, .exact `A] }
  assertEq "digest is allowlist-order independent" orderA.digest orderB.digest
  let unknownsAllowed := { strict with unknownPolicy := .allow }
  assertTrue "digest distinguishes unknown treatment" (strict.digest != unknownsAllowed.digest)

run_cmd do
  let base := Policy.strictPolicy
  let unmodified := Cli.applyPolicyModifiers base #[]
  assertEq "unmodified identifier" "strict" unmodified.identifier
  let modifiers : Array Cli.PolicyModifier := #[.allowTypeclasses, .allowPackage `M.P]
  let reversed : Array Cli.PolicyModifier := #[.allowPackage `M.P, .allowTypeclasses]
  let composed := Cli.applyPolicyModifiers base modifiers
  let composedReversed := Cli.applyPolicyModifiers base reversed
  assertEq "modifier identifier records every modification"
    "strict+allow-package:M.P+allow-typeclasses" composed.identifier
  assertEq "modifier identifier is order independent"
    composed.identifier composedReversed.identifier
  assertEq "modifier digest is order independent" composed.digest composedReversed.digest
  assertEq "modifier semantics typeclass" AssumptionTreatment.allow composed.typeclassPolicy
  let allowed ← requireAt "modifier package allowlist" composed.permittedPackageTypes 0
  assertEq "modifier package pattern" (NamePattern.exact `M.P) allowed
  assertTrue "modified digest differs from base" (base.digest != composed.digest)
  let warned := Cli.applyPolicyModifiers base #[.warnUnknowns]
  assertEq "warn modifier semantics" AssumptionTreatment.warn warned.unknownPolicy
  assertEq "warn modifier identifier" "strict+warn-unknowns" warned.identifier
