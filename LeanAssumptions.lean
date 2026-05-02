import LeanAssumptions.Version
import LeanAssumptions.Core
import LeanAssumptions.Policy
import LeanAssumptions.Render
import LeanAssumptions.Delta
import LeanAssumptions.Cluster
import LeanAssumptions.Baseline
import LeanAssumptions.Command
import LeanAssumptions.Cli

/-!
`lean-assumptions` public root module.

This root exposes package metadata, certified classification/policy entry
points, stable report rendering, artifact delta reporting, failure clustering,
baseline comparison, the Lean command surface, and CLI support.
-/

open Lean Elab Command

namespace LeanAssumptions

/--
Public certified inspection entry point.

This thin adapter exposes certified-path declaration inspection without adding
rendering or command syntax. Policy evaluation is available separately through
`LeanAssumptions.Policy`.
-/
def inspectDeclaration (declName : Lean.Name) : CommandElabM Core.AssumptionReport :=
  Core.inspectDeclaration declName

/--
Public certified inspection entry point with explicit alias transparency.

The default `inspectDeclaration` is equivalent to `.none`; callers that want
reducible alias expansion must request it here so report artifacts can state
the chosen mode.
-/
def inspectDeclarationWithTransparency
    (transparencyMode : Core.TransparencyMode)
    (declName : Lean.Name) : CommandElabM Core.AssumptionReport :=
  Core.inspectDeclarationWithTransparency transparencyMode declName

end LeanAssumptions
