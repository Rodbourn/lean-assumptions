import LeanAssumptions.Render

/-!
Public `#assumptions` commands for assumption-surface reports.

Commands are support-layer adapters: they inspect the requested declaration,
evaluate a policy, and render the resulting report without changing trusted
core or policy decisions.

The bare commands use the hidden-surface policy, which flags only assumptions
the reader cannot see in the statement as written — packaged proposition
fields, proof-carrying data, unexpanded aliases, and unknowns. The `strict`
variants fail every unapproved assumption, including visible proposition
binders and typeclass arguments, for certification workflows.

Examples:

```lean
#assumptions MyTheorem
#assumptions strict MyTheorem
#assumptions_json MyTheorem
#assumptions_json strict MyTheorem
```
-/

open Lean Elab Command

namespace LeanAssumptions.Command

open LeanAssumptions

/-- Render the text report for a declaration under a policy. -/
private def renderTextReport (policy : Policy.PolicyConfig) (declName : Lean.Name) :
    CommandElabM String := do
  let report ← Core.inspectDeclarationWithTransparency policy.transparencyMode declName
  let evaluation := Policy.evaluate policy report
  pure (Render.renderText policy report evaluation)

/-- Render the JSON report for a declaration under a policy. -/
private def renderJsonReport (policy : Policy.PolicyConfig) (declName : Lean.Name) :
    CommandElabM String := do
  let report ← Core.inspectDeclarationWithTransparency policy.transparencyMode declName
  let evaluation := Policy.evaluate policy report
  pure (Render.renderJsonString policy report evaluation)

/-- Emit a string as a Lean informational message. -/
private def logReport (text : String) : CommandElabM Unit :=
  logInfo m!"{text}"

-- `&"strict"` is a non-reserved keyword: it selects the strict variant here
-- without reserving `strict` as a global token, so downstream code can keep
-- using `strict` as an ordinary identifier.
syntax (name := assumptionsCmd) "#assumptions" (&"strict")? ident : command
syntax (name := assumptionsJsonCmd) "#assumptions_json" (&"strict")? ident : command

elab_rules : command
  | `(command| #assumptions $decl:ident) => do
    logReport (← renderTextReport Policy.hiddenSurfacePolicy decl.getId)
  | `(command| #assumptions strict $decl:ident) => do
    logReport (← renderTextReport Policy.strictPolicy decl.getId)
  | `(command| #assumptions_json $decl:ident) => do
    logReport (← renderJsonReport Policy.hiddenSurfacePolicy decl.getId)
  | `(command| #assumptions_json strict $decl:ident) => do
    logReport (← renderJsonReport Policy.strictPolicy decl.getId)

end LeanAssumptions.Command
