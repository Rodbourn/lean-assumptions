import LeanAssumptions

/-!
Runnable example showing a statement-surface assumption hidden inside a package.

Run it from the repository root with:

```text
lake env lean Examples/HiddenPackage.lean
```
-/

namespace Examples.HiddenPackage

/-- Data packaged with a proposition-valued certificate field. -/
structure CertifiedValue where
  value : Nat
  certified : value = value

/--
A theorem whose visible argument is a package.

The package field `certified` is still part of the theorem's statement-level
assumption surface.
-/
theorem usesCertifiedValue (pkg : CertifiedValue) : pkg.value = pkg.value := rfl

#print axioms Examples.HiddenPackage.usesCertifiedValue
#print assumptions Examples.HiddenPackage.usesCertifiedValue
#print assumption_tree Examples.HiddenPackage.usesCertifiedValue
#print assumption_json Examples.HiddenPackage.usesCertifiedValue

end Examples.HiddenPackage
