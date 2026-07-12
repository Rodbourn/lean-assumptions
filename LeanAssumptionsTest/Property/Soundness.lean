import LeanAssumptions
import LeanAssumptionsTest.TestUtil

/-!
Property-based soundness oracle for the certified classifier.

This module GENERATES a corpus of theorem declarations, each embedding a
marked proposition by construction, plus data-only mirror controls, and then
asserts the conservatism oracle over every generated declaration:

- every positive (proposition-embedding) shape must FAIL strict policy
- every negative (data-only) control must PASS strict policy

The generator composes embedding sites (direct proposition, structure field,
nested package, non-structure inductive constructor field, function codomain,
`Subtype` predicate, `PSigma` payload, tuple component, list element) with
explicit, implicit, and strict-implicit binder kinds, so the oracle sweeps the
cartesian behavior space rather than hand-picked examples. Instance-implicit
binders are exercised by the fixture corpus instead: under strict policy every
instance binder fails regardless of content, and an allowlisted typeclass owns
its internal fields by design, so they carry no positive/negative signal here.

A false pass from this oracle is a certified-path correctness incident: stop,
minimize the reproducer, and fix with a regression test before proceeding
(`AGENTS.md`, non-negotiable principles 1-3).
-/

open Lean Elab Command
open LeanAssumptions
open LeanAssumptions.Core
open LeanAssumptions.Policy
open LeanAssumptionsTest

namespace LeanAssumptionsTest.Property

/-- The marked proposition every positive shape embeds. -/
def MarkedProp : Prop := 1 = 1

/-- A structure embedding the marked proposition as a field. -/
structure MarkedField where
  value : Nat
  marked : MarkedProp

/-- A structure nesting the marked package one level deeper. -/
structure MarkedNested where
  inner : MarkedField

/-- A non-structure inductive whose constructor carries the marked proof. -/
inductive MarkedCarrier : Type where
  /-- Wrap a marked proof as data. -/
  | intro (h : MarkedProp)

/-- A data-only mirror of `MarkedField`. -/
structure PlainField where
  value : Nat
  extra : Nat

/-- A data-only mirror of `MarkedNested`. -/
structure PlainNested where
  inner : PlainField

/-- A data-only mirror of `MarkedCarrier`. -/
inductive PlainCarrier : Type where
  /-- Wrap plain data. -/
  | intro (n : Nat)

/-- Positive embedding sites: each type provably carries `MarkedProp`. -/
def positiveTypeSources : Array (String × String) := #[
  ("direct", "LeanAssumptionsTest.Property.MarkedProp"),
  ("field", "LeanAssumptionsTest.Property.MarkedField"),
  ("nested", "LeanAssumptionsTest.Property.MarkedNested"),
  ("carrier", "LeanAssumptionsTest.Property.MarkedCarrier"),
  ("codomain", "Unit → LeanAssumptionsTest.Property.MarkedField"),
  ("subtype", "{ n : Nat // n = 1 }"),
  ("psigma", "PSigma fun _ : Nat => LeanAssumptionsTest.Property.MarkedProp"),
  ("pair", "Nat × LeanAssumptionsTest.Property.MarkedField"),
  ("listed", "List LeanAssumptionsTest.Property.MarkedCarrier")
]

/-- Negative control sites: data-only mirrors that must keep passing. -/
def negativeTypeSources : Array (String × String) := #[
  ("nat", "Nat"),
  ("field", "LeanAssumptionsTest.Property.PlainField"),
  ("nested", "LeanAssumptionsTest.Property.PlainNested"),
  ("carrier", "LeanAssumptionsTest.Property.PlainCarrier"),
  ("codomain", "Unit → LeanAssumptionsTest.Property.PlainField"),
  ("pair", "Nat × LeanAssumptionsTest.Property.PlainField"),
  ("listed", "List LeanAssumptionsTest.Property.PlainCarrier"),
  ("function", "Nat → List Nat")
]

/-- The binder-kind dimension swept for every embedding site. -/
def binderKindLabels : List String := ["exp", "imp", "strict"]

/-- Parse a type source string into term syntax. -/
private def parseTypeTerm (source : String) : CommandElabM Term := do
  match Parser.runParserCategory (← getEnv) `term source "<property-generator>" with
  | .ok stx => pure ⟨stx⟩
  | .error error => throwError "property generator could not parse {source}: {error}"

/-- Declare the three binder-kind variants of one generated shape. -/
private def declareShapes (prefixLabel typeLabel : String) (source : String) :
    CommandElabM Unit := do
  let type ← parseTypeTerm source
  let mkShapeName (kind : String) : Ident :=
    mkIdent (Name.mkSimple s!"{prefixLabel}_{typeLabel}_{kind}")
  elabCommand (← `(command|
    theorem $(mkShapeName "exp") (x : $type) : True := by
      let _ := x
      trivial))
  elabCommand (← `(command|
    theorem $(mkShapeName "imp") {x : $type} : True := by
      let _ := x
      trivial))
  elabCommand (← `(command|
    theorem $(mkShapeName "strict") ⦃x : $type⦄ : True := by
      let _ := x
      trivial))

run_cmd do
  for (typeLabel, source) in positiveTypeSources do
    declareShapes "positive" typeLabel source
  for (typeLabel, source) in negativeTypeSources do
    declareShapes "negative" typeLabel source

/-- Evaluate one generated declaration against strict policy. -/
private def strictResultOf (declName : Lean.Name) : CommandElabM PolicyResult := do
  let report ← LeanAssumptions.Core.inspectDeclaration declName
  pure (Policy.evaluate Policy.strictPolicy report).result

run_cmd do
  -- The conservatism oracle. Every positive must fail; every negative must
  -- pass. Both directions matter: losing the negatives would let the
  -- classifier drift into rejecting everything, which is uselessly "sound".
  let mut positives := 0
  let mut negatives := 0
  for (typeLabel, _) in positiveTypeSources do
    for kind in binderKindLabels do
      let declName := `LeanAssumptionsTest.Property ++
        Name.mkSimple s!"positive_{typeLabel}_{kind}"
      let result ← strictResultOf declName
      unless result == PolicyResult.fail do
        throwError "SOUNDNESS ORACLE VIOLATION: {declName} embeds the marked \
          proposition but strict policy reported {repr result}. Treat as a \
          certified-path correctness incident."
      positives := positives + 1
  for (typeLabel, _) in negativeTypeSources do
    for kind in binderKindLabels do
      let declName := `LeanAssumptionsTest.Property ++
        Name.mkSimple s!"negative_{typeLabel}_{kind}"
      let result ← strictResultOf declName
      unless result == PolicyResult.pass do
        throwError "conservatism drift: data-only control {declName} reported \
          {repr result} under strict policy instead of pass."
      negatives := negatives + 1
  assertEq "oracle positive coverage" (positiveTypeSources.size * 3) positives
  assertEq "oracle negative coverage" (negativeTypeSources.size * 3) negatives

end LeanAssumptionsTest.Property
