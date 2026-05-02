import LeanAssumptions.Render

/-!
Public `#print` commands for assumption-surface reports.

Commands are support-layer adapters: they inspect the requested declaration,
evaluate the strict policy, and render the resulting report without changing
certified core or policy decisions.

Examples:

```lean
#print assumptions MyTheorem
#print assumption_tree MyTheorem
#print assumption_json MyTheorem
```
-/

open Lean Elab Command

namespace LeanAssumptions.Command

open LeanAssumptions

/-- Render the strict-policy text report for a declaration name. -/
private def renderStrictText (declName : Lean.Name) : CommandElabM String := do
  let report ← Core.inspectDeclaration declName
  let evaluation := Policy.evaluate Policy.strictPolicy report
  pure (Render.renderText Policy.strictPolicy report evaluation)

/-- Render the strict-policy JSON report for a declaration name. -/
private def renderStrictJson (declName : Lean.Name) : CommandElabM String := do
  let report ← Core.inspectDeclaration declName
  let evaluation := Policy.evaluate Policy.strictPolicy report
  pure (Render.renderJsonString Policy.strictPolicy report evaluation)

/-- Emit a string as a Lean informational message. -/
private def logReport (text : String) : CommandElabM Unit :=
  logInfo m!"{text}"

syntax (name := printAssumptions) "#print" "assumptions" ident : command
syntax (name := printAssumptionTree) "#print" "assumption_tree" ident : command
syntax (name := printAssumptionJson) "#print" "assumption_json" ident : command

elab_rules : command
  | `(command| #print assumptions $decl:ident) => do
    logReport (← renderStrictText decl.getId)
  | `(command| #print assumption_tree $decl:ident) => do
    logReport (← renderStrictText decl.getId)
  | `(command| #print assumption_json $decl:ident) => do
    logReport (← renderStrictJson decl.getId)

end LeanAssumptions.Command
