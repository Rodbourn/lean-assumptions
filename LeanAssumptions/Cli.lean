import Lean
import Lean.Data.Json.Parser
import LeanAssumptions.Cluster
import LeanAssumptions.Delta
import LeanAssumptions.Render

/-!
Command-line support for `lean-assumptions`.

The CLI is a support-layer adapter. It parses arguments and policy files, loads
requested modules, and runs a generated command-elaboration action that delegates
inspection to `LeanAssumptions.Core`, policy evaluation to
`LeanAssumptions.Policy`, audit output to `LeanAssumptions.Render`, and
artifact comparison and clustering to `LeanAssumptions.Delta` and
`LeanAssumptions.Cluster`.
-/

open Lean Elab Command

namespace LeanAssumptions.Cli

open LeanAssumptions
open LeanAssumptions.Policy

/-- CLI output modes. -/
inductive OutputFormat where
  | text
  | json
  deriving DecidableEq, Repr, Inhabited

/-- Parsed delta-mode input paths. -/
structure DeltaConfig where
  baselinePath : System.FilePath
  currentPath : System.FilePath
  deriving Repr

/-- Parsed cluster-mode input path. -/
structure ClusterConfig where
  artifactPath : System.FilePath
  deriving Repr

/-- Parsed CLI configuration. -/
structure Config where
  modules : Array Lean.Name := #[]
  declarations : Array Lean.Name := #[]
  scanModules : Array Lean.Name := #[]
  delta? : Option DeltaConfig := none
  cluster? : Option ClusterConfig := none
  format : OutputFormat := .text
  policy : PolicyConfig := Policy.strictPolicy
  policyConfigured : Bool := false
  deriving Repr

/-- Usage text for invalid invocations. -/
def usage : String :=
  "usage: lean-assumptions --module <Module> (--decl <Name> | --scan-module <Module>) [--format text|json] [--policy <file>] [--allow-direct <Name>] [--allow-package <Name>] [--allow-typeclasses] [--allow-unknowns]\n" ++
  "   or: lean-assumptions --diff <baseline.json> <current.json> [--format text|json]\n" ++
  "   or: lean-assumptions --cluster <audit.json> [--format text|json]"

/-- Return whether `a` sorts before `b` in public dotted-name order. -/
private def nameLt (a b : Lean.Name) : Bool :=
  toString a < toString b

/-- Insert a name into a sorted list. -/
private def insertName (name : Lean.Name) : List Lean.Name -> List Lean.Name
  | [] => [name]
  | head :: rest =>
    if nameLt name head then
      name :: head :: rest
    else
      head :: insertName name rest

/-- Sort names deterministically by dotted-name order. -/
private def sortNames (names : Array Lean.Name) : Array Lean.Name :=
  names.foldl (fun sorted name => insertName name sorted) [] |>.toArray

/-- Return declarations imported from a module, sorted deterministically. -/
def declarationsInModule (moduleName : Lean.Name) : CommandElabM (Array Lean.Name) := do
  let env ← getEnv
  let some moduleIdx := env.getModuleIdx? moduleName
    | throwError "module is not imported: {moduleName}"
  let names :=
    env.constants.toList.filterMap fun entry =>
      let declName := entry.fst
      if env.getModuleIdxFor? declName == some moduleIdx then
        some declName
      else
        none
  pure (sortNames names.toArray)

/-- Inspect and evaluate a declaration under a policy. -/
private def inspectArtifact (policy : PolicyConfig) (declName : Lean.Name) :
    CommandElabM Render.ReportArtifact := do
  let report ← Core.inspectDeclarationWithTransparency policy.transparencyMode declName
  let evaluation := Policy.evaluate policy report
  pure { report := report, evaluation := evaluation }

/-- Expand explicit declarations plus module scans into deterministic report artifacts. -/
def inspectRequested
    (policy : PolicyConfig)
    (declarations : Array Lean.Name)
    (scanModules : Array Lean.Name) : CommandElabM (Array Render.ReportArtifact) := do
  let mut names := declarations
  for moduleName in scanModules do
    names := names ++ (← declarationsInModule moduleName)
  let mut artifacts : Array Render.ReportArtifact := #[]
  for declName in names do
    artifacts := artifacts.push (← inspectArtifact policy declName)
  pure artifacts

/-- Run the generated command-elaboration body used by the CLI executable. -/
def runGenerated
    (format : OutputFormat)
    (policy : PolicyConfig)
    (declarations : Array Lean.Name)
    (scanModules : Array Lean.Name)
    (emitOutput : Bool := true) : CommandElabM Unit := do
  let artifacts ← inspectRequested policy declarations scanModules
  let output :=
    match format with
    | .text => Render.renderBatchText policy artifacts
    | .json => Render.renderBatchJsonString policy artifacts
  if emitOutput then
    IO.print output
  if artifacts.any (fun artifact => Render.policyResultIsFailure artifact.evaluation.result) then
    throwError "lean-assumptions policy failure"

/-- Parse an output-format string. -/
private def parseOutputFormat (value : String) : Except String OutputFormat :=
  match value with
  | "text" => .ok .text
  | "json" => .ok .json
  | other => .error s!"unsupported output format: {other}"

/-- Parse a transparency-mode string. -/
private def parseTransparencyMode (value : String) : Except String Core.TransparencyMode :=
  match value with
  | "none" => .ok .none
  | "reducible" => .ok .reducible
  | "recursive_normalization" => .ok .recursiveNormalization
  | other => .error s!"unsupported transparency mode: {other}"

/-- Parse an assumption-treatment string. -/
private def parseTreatment (value : String) : Except String AssumptionTreatment :=
  match value with
  | "allow" => .ok .allow
  | "warn" => .ok .warn
  | "fail" => .ok .fail
  | other => .error s!"unsupported treatment: {other}"

/-- Return an optional object field from a JSON object. -/
private def optionalObjVal (json : Lean.Json) (key : String) : Except String (Option Lean.Json) :=
  match json.getObjVal? key with
  | .ok value => .ok (some value)
  | .error _ => .ok none

/-- Read an optional string field from a JSON policy object. -/
private def optionalString (json : Lean.Json) (key fallback : String) : Except String String := do
  match ← optionalObjVal json key with
  | none => pure fallback
  | some value => value.getStr?

/-- Read an optional treatment field from a JSON policy object. -/
private def optionalTreatment
    (json : Lean.Json)
    (key : String)
    (fallback : AssumptionTreatment) : Except String AssumptionTreatment := do
  match ← optionalObjVal json key with
  | none => pure fallback
  | some value => parseTreatment (← value.getStr?)

/-- Parse a JSON policy name pattern. -/
private def parseNamePattern (json : Lean.Json) : Except String NamePattern := do
  match json with
  | .str value => pure (.exact value.toName)
  | _ =>
    match ← optionalObjVal json "exact" with
    | some value => pure (.exact (← value.getStr?).toName)
    | none =>
      match ← optionalObjVal json "prefix" with
      | some value => pure (.prefix (← value.getStr?).toName)
      | none => .error "name pattern must be a string or object with exact/prefix"

/-- Parse an optional JSON array of name patterns. -/
private def optionalNamePatterns (json : Lean.Json) (key : String) : Except String (Array NamePattern) := do
  match ← optionalObjVal json key with
  | none => pure #[]
  | some value =>
    let entries ← value.getArr?
    entries.mapM parseNamePattern

/-- Parse a versioned JSON policy file. -/
def parsePolicyJson (json : Lean.Json) : Except String PolicyConfig := do
  let version ← (← json.getObjVal? "version").getNat?
  if version != 1 then
    throw s!"unsupported policy version: {version}"
  let identifier ← optionalString json "identifier" "policy-file"
  let transparencyValue ← optionalString json "transparency_mode" "none"
  let transparencyMode ← parseTransparencyMode transparencyValue
  let permittedDirectProps ← optionalNamePatterns json "permit_direct_props"
  let permittedPackageTypes ← optionalNamePatterns json "permit_package_types"
  let typeclassPolicy ← optionalTreatment json "typeclass_policy" .fail
  let unknownPolicy ← optionalTreatment json "unknown_policy" .fail
  pure {
    identifier := identifier
    transparencyMode := transparencyMode
    permittedDirectProps := permittedDirectProps
    permittedPackageTypes := permittedPackageTypes
    typeclassPolicy := typeclassPolicy
    unknownPolicy := unknownPolicy
    aliasPolicy := .fail
  }

/-- Read and parse a versioned JSON policy file. -/
private def readPolicyFile (path : System.FilePath) : IO PolicyConfig := do
  let text ← IO.FS.readFile path
  match Lean.Json.parse text with
  | .ok json =>
    match parsePolicyJson json with
    | .ok policy => pure policy
    | .error error => throw (IO.userError error)
  | .error error => throw (IO.userError error)

/-- Parse CLI arguments into a configuration. -/
private def parseArgsAux : List String -> Config -> IO Config
  | [], config => pure config
  | "--module" :: value :: rest, config =>
    parseArgsAux rest { config with modules := config.modules.push value.toName }
  | "--decl" :: value :: rest, config =>
    parseArgsAux rest { config with declarations := config.declarations.push value.toName }
  | "--scan-module" :: value :: rest, config =>
    parseArgsAux rest { config with scanModules := config.scanModules.push value.toName }
  | "--diff" :: baseline :: current :: rest, config =>
    if config.delta?.isSome then
      throw (IO.userError s!"multiple --diff options are not supported\n{usage}")
    else if config.cluster?.isSome then
      throw (IO.userError s!"--diff cannot be combined with --cluster\n{usage}")
    else
      parseArgsAux rest {
        config with
        delta? := some { baselinePath := baseline, currentPath := current }
      }
  | "--cluster" :: artifact :: rest, config =>
    if config.cluster?.isSome then
      throw (IO.userError s!"multiple --cluster options are not supported\n{usage}")
    else if config.delta?.isSome then
      throw (IO.userError s!"--cluster cannot be combined with --diff\n{usage}")
    else
      parseArgsAux rest {
        config with
        cluster? := some { artifactPath := artifact }
      }
  | "--format" :: value :: rest, config =>
    match parseOutputFormat value with
    | .ok format => parseArgsAux rest { config with format := format }
    | .error error => throw (IO.userError error)
  | "--policy" :: value :: rest, config => do
    let policy ← readPolicyFile value
    parseArgsAux rest { config with policy := policy, policyConfigured := true }
  | "--allow-direct" :: value :: rest, config =>
    let policy := {
      config.policy with
      permittedDirectProps := config.policy.permittedDirectProps.push (.exact value.toName)
    }
    parseArgsAux rest { config with policy := policy, policyConfigured := true }
  | "--allow-package" :: value :: rest, config =>
    let policy := {
      config.policy with
      permittedPackageTypes := config.policy.permittedPackageTypes.push (.exact value.toName)
    }
    parseArgsAux rest { config with policy := policy, policyConfigured := true }
  | "--allow-typeclasses" :: rest, config =>
    parseArgsAux rest {
      config with
      policy := { config.policy with typeclassPolicy := .allow }
      policyConfigured := true
    }
  | "--allow-unknowns" :: rest, config =>
    parseArgsAux rest {
      config with
      policy := { config.policy with unknownPolicy := .allow }
      policyConfigured := true
    }
  | "--warn-unknowns" :: rest, config =>
    parseArgsAux rest {
      config with
      policy := { config.policy with unknownPolicy := .warn }
      policyConfigured := true
    }
  | "--help" :: _, _ => throw (IO.userError usage)
  | option :: _, _ => throw (IO.userError s!"unknown or incomplete option: {option}\n{usage}")

/-- Parse CLI arguments and validate that there is work to do. -/
def parseArgs (args : Array String) : IO Config := do
  let config ← parseArgsAux args.toList {}
  match config.delta?, config.cluster? with
  | some _, some _ =>
    throw (IO.userError s!"--diff cannot be combined with --cluster\n{usage}")
  | some _, none =>
    if !config.modules.isEmpty || !config.declarations.isEmpty || !config.scanModules.isEmpty ||
        config.policyConfigured then
      throw (IO.userError s!"--diff cannot be combined with audit modules, declarations, scans, or policy options\n{usage}")
    pure config
  | none, some _ =>
    if !config.modules.isEmpty || !config.declarations.isEmpty || !config.scanModules.isEmpty ||
        config.policyConfigured then
      throw (IO.userError s!"--cluster cannot be combined with audit modules, declarations, scans, or policy options\n{usage}")
    pure config
  | none, none =>
    if config.modules.isEmpty then
      throw (IO.userError s!"at least one --module is required\n{usage}")
    if config.declarations.isEmpty && config.scanModules.isEmpty then
      throw (IO.userError s!"at least one --decl or --scan-module is required\n{usage}")
    pure config

/-- Run a command-elaboration action in an imported environment. -/
private def runCommandInEnv
    (env : Lean.Environment)
    (opts : Lean.Options)
    (action : CommandElabM Unit) : IO UInt32 := do
  let inputCtx := Parser.mkInputContext "" "<lean-assumptions-cli>"
  let context : Command.Context := {
    fileName := inputCtx.fileName
    fileMap := inputCtx.fileMap
    snap? := none
    cancelTk? := none
  }
  let state := Command.mkState env {} opts
  match ← EIO.toIO' ((action context).run state) with
  | .ok (_, newState) =>
    if Lean.MessageLog.hasErrors newState.messages then
      for message in Lean.MessageLog.toList newState.messages do
        if message.severity == MessageSeverity.error then
          IO.eprintln (← message.toString)
      pure 1
    else
      pure 0
  | .error exception =>
    IO.eprintln (← exception.toMessageData.toString)
    pure 1

/-- Run an already parsed CLI configuration in an imported environment. -/
private def runConfigInImportedEnv
    (env : Lean.Environment)
    (opts : Lean.Options)
    (config : Config)
    (emitOutput : Bool) : IO UInt32 := do
  match config.delta?, config.cluster? with
  | some deltaConfig, none =>
    let report ← Delta.readDeltaReport deltaConfig.baselinePath deltaConfig.currentPath
    let output :=
      match config.format with
      | .text => Delta.renderText report
      | .json => Delta.renderJsonString report
    if emitOutput then
      IO.print output
    pure 0
  | none, some clusterConfig =>
    let report ← Cluster.readClusterReport clusterConfig.artifactPath
    let output :=
      match config.format with
      | .text => Cluster.renderText report
      | .json => Cluster.renderJsonString report
    if emitOutput then
      IO.print output
    pure 0
  | some _, some _ =>
    IO.eprintln s!"--diff cannot be combined with --cluster\n{usage}"
    pure 2
  | none, none =>
    runCommandInEnv env opts
      (runGenerated config.format config.policy config.declarations config.scanModules emitOutput)

/--
Run the CLI support path against an environment that has already imported the
requested audit modules.

This keeps embedding and integration tests from paying repeated module-import
costs while preserving the normal argument parser, policy handling, renderers,
and exit-code semantics. The ordinary executable path should use `run`, which
constructs the imported environment from `--module` arguments.
-/
def runWithImportedEnv
    (env : Lean.Environment)
    (opts : Lean.Options)
    (args : Array String)
    (emitOutput : Bool := true) : IO UInt32 := do
  try
    let config ← parseArgs args
    runConfigInImportedEnv env opts config emitOutput
  catch error =>
    IO.eprintln error.toString
    pure 2

/-- Run the CLI support path in-process and return a CI-friendly exit code. -/
def run (args : Array String) : IO UInt32 := do
  try
    let config ← parseArgs args
    match config.delta?, config.cluster? with
    | some deltaConfig, none =>
      let report ← Delta.readDeltaReport deltaConfig.baselinePath deltaConfig.currentPath
      let output :=
        match config.format with
        | .text => Delta.renderText report
        | .json => Delta.renderJsonString report
      IO.print output
      pure 0
    | none, some clusterConfig =>
      let report ← Cluster.readClusterReport clusterConfig.artifactPath
      let output :=
        match config.format with
        | .text => Cluster.renderText report
        | .json => Cluster.renderJsonString report
      IO.print output
      pure 0
    | some _, some _ =>
      IO.eprintln s!"--diff cannot be combined with --cluster\n{usage}"
      pure 2
    | none, none =>
      let imports := #[{ module := `LeanAssumptions : Lean.Import }] ++
        config.modules.map fun moduleName => ({ module := moduleName : Lean.Import })
      let opts : Lean.Options := {}
      Lean.initSearchPath (← Lean.findSysroot)
      let env ← Lean.importModules imports opts
      runConfigInImportedEnv env opts config true
  catch error =>
    IO.eprintln error.toString
    pure 2

end LeanAssumptions.Cli
