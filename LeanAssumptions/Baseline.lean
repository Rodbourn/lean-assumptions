import Lean.Data.Json.Parser
import LeanAssumptions.JsonUtil
import LeanAssumptions.Version

/-!
Support-layer baseline comparison for rendered audit artifacts.

Baseline mode compares JSON artifacts already emitted by `lean-assumptions`.
It does not inspect Lean environments, reclassify theorem surfaces, alter
policy semantics, or migrate artifacts between schema versions.
-/

namespace LeanAssumptions.Baseline

/--
Stable identity for a policy finding across baseline comparisons.

Severity and expression renderings are intentionally excluded. A policy
warn/fail treatment change should not churn the baseline, while declaration
names, finding kind/category, report path, and type name define the
statement-surface assumption being tracked.
-/
structure FindingIdentity where
  declarationName : String
  kind : String
  category : String
  path : Array String
  typeName? : Option String
  deriving BEq, Repr, Inhabited

/-- Metadata preserved from a baseline/current audit artifact. -/
structure ArtifactMetadata where
  schemaVersion : String
  leanVersion : String
  policyIdentifier : String
  transparencyMode : String
  deriving BEq, Repr, Inhabited

/-- Parsed baseline/current artifact reduced to policy-finding identities. -/
structure AuditArtifact where
  metadata : ArtifactMetadata
  findings : Array FindingIdentity
  deriving BEq, Repr, Inhabited

/-- Deterministic baseline comparison result. -/
structure BaselineComparison where
  baseline : AuditArtifact
  current : AuditArtifact
  addedFindings : Array FindingIdentity
  removedFindings : Array FindingIdentity
  deriving BEq, Repr, Inhabited

/-- Public baseline status. -/
inductive BaselineStatus where
  | pass
  | improvement
  | regression
  deriving BEq, DecidableEq, Repr, Inhabited

/-- Join strings with a separator without depending on map iteration order. -/
private def joinWith (separator : String) : List String -> String
  | [] => ""
  | [item] => item
  | item :: rest => item ++ separator ++ joinWith separator rest

/-- Return an optional object field from a JSON object. -/
private def optionalObjVal (json : Lean.Json) (key : String) : Except String (Option Lean.Json) :=
  match json.getObjVal? key with
  | .ok value => .ok (some value)
  | .error _ => .ok none

/-- Read a required JSON string field. -/
private def requiredString (json : Lean.Json) (key : String) : Except String String := do
  (← json.getObjVal? key).getStr?

/-- Read an optional JSON string field, treating JSON null as absent. -/
private def optionalString (json : Lean.Json) (key : String) : Except String (Option String) := do
  match ← optionalObjVal json key with
  | none => pure none
  | some .null => pure none
  | some value => pure (some (← value.getStr?))

/-- Extract report objects from a batch JSON artifact. -/
private def reportObjects (json : Lean.Json) : Except String (Array Lean.Json) := do
  match ← optionalObjVal json "reports" with
  | some reports => reports.getArr?
  | none => throw "baseline artifacts must be batch JSON emitted by lean-assumptions"

/-- Parse one public finding into the baseline identity contract. -/
def parseFindingIdentity
    (declarationName : String)
    (json : Lean.Json) : Except String FindingIdentity := do
  let pathJson ← (← json.getObjVal? "path").getArr?
  let path ← pathJson.mapM Lean.Json.getStr?
  pure {
    declarationName := declarationName
    kind := ← requiredString json "kind"
    category := ← requiredString json "category"
    path := path
    typeName? := ← optionalString json "type_name"
  }

/-- Parse all policy-finding identities from one report object. -/
private def parseReportFindings (json : Lean.Json) : Except String (Array FindingIdentity) := do
  let declarationName ← requiredString json "target"
  let findings ← (← json.getObjVal? "policy_findings").getArr?
  findings.mapM (parseFindingIdentity declarationName)

/-- Render an optional string into a stable comparison key. -/
private def optionKey : Option String -> String
  | some value => value
  | none => ""

/-- Stable total-order key for finding identities. -/
private def FindingIdentity.key (identity : FindingIdentity) : String :=
  joinWith "|" [
    identity.declarationName,
    identity.kind,
    identity.category,
    joinWith "." identity.path.toList,
    optionKey identity.typeName?
  ]

/-- Return whether one finding identity sorts before another. -/
private def findingLt (left right : FindingIdentity) : Bool :=
  left.key < right.key

/-- Insert one finding identity into a deterministic sorted unique list. -/
private def insertFinding (identity : FindingIdentity) : List FindingIdentity -> List FindingIdentity
  | [] => [identity]
  | head :: rest =>
    if identity == head then
      head :: rest
    else if findingLt identity head then
      identity :: head :: rest
    else
      head :: insertFinding identity rest

/-- Sort finding identities deterministically and drop duplicates. -/
def sortUniqueFindings (findings : Array FindingIdentity) : Array FindingIdentity :=
  findings.foldl (fun sorted finding => insertFinding finding sorted) [] |>.toArray

/-- Parse a batch JSON artifact into baseline comparison data. -/
def parseAuditArtifact (json : Lean.Json) : Except String AuditArtifact := do
  let reports ← reportObjects json
  let nestedFindings ← reports.mapM parseReportFindings
  let findings := nestedFindings.foldl (fun acc reportFindings => acc ++ reportFindings) #[]
  pure {
    metadata := {
      schemaVersion := ← requiredString json "schema_version"
      leanVersion := ← requiredString json "lean_version"
      policyIdentifier := ← requiredString json "policy_identifier"
      transparencyMode := ← requiredString json "transparency_mode"
    }
    findings := sortUniqueFindings findings
  }

/-- Parse a batch artifact from a JSON string. -/
def parseAuditArtifactString (text : String) : Except String AuditArtifact := do
  let json ←
    match Lean.Json.parse text with
    | .ok json => pure json
    | .error error => throw error
  parseAuditArtifact json

/-- Read and parse a batch audit artifact from disk. -/
def readAuditArtifact (path : System.FilePath) : IO AuditArtifact := do
  let text ← IO.FS.readFile path
  match parseAuditArtifactString text with
  | .ok artifact => pure artifact
  | .error error => throw (IO.userError error)

/-- Merge two sorted finding lists into added and removed identities. -/
private def compareFindings :
    List FindingIdentity -> List FindingIdentity -> List FindingIdentity × List FindingIdentity
  | [], [] => ([], [])
  | [], current :: currentRest =>
    let (added, removed) := compareFindings [] currentRest
    (current :: added, removed)
  | baseline :: baselineRest, [] =>
    let (added, removed) := compareFindings baselineRest []
    (added, baseline :: removed)
  | baseline :: baselineRest, current :: currentRest =>
    if baseline == current then
      compareFindings baselineRest currentRest
    else if findingLt baseline current then
      let (added, removed) := compareFindings baselineRest (current :: currentRest)
      (added, baseline :: removed)
    else
      let (added, removed) := compareFindings (baseline :: baselineRest) currentRest
      (current :: added, removed)

/-- Compare parsed baseline and current artifacts. -/
def compareArtifacts (baseline current : AuditArtifact) : Except String BaselineComparison := do
  if baseline.metadata.schemaVersion != jsonSchemaVersion then
    throw s!"baseline schema_version {baseline.metadata.schemaVersion} does not match current schema_version {jsonSchemaVersion}; regenerate the baseline"
  if current.metadata.schemaVersion != jsonSchemaVersion then
    throw s!"current schema_version {current.metadata.schemaVersion} does not match tool schema_version {jsonSchemaVersion}"
  let (added, removed) := compareFindings baseline.findings.toList current.findings.toList
  pure {
    baseline := baseline
    current := current
    addedFindings := added.toArray
    removedFindings := removed.toArray
  }

/-- Compare two JSON artifact strings. -/
def compareArtifactStrings (baselineText currentText : String) : Except String BaselineComparison := do
  let baseline ← parseAuditArtifactString baselineText
  let current ← parseAuditArtifactString currentText
  compareArtifacts baseline current

/-- Compute public baseline status from added/removed finding sets. -/
def BaselineComparison.status (comparison : BaselineComparison) : BaselineStatus :=
  if !comparison.addedFindings.isEmpty then
    .regression
  else if !comparison.removedFindings.isEmpty then
    .improvement
  else
    .pass

/-- Map a baseline comparison to the CI exit code. -/
def BaselineComparison.exitCode (comparison : BaselineComparison) : UInt32 :=
  match comparison.status with
  | .regression => 1
  | .pass | .improvement => 0

/-- Render a baseline status using public text spelling. -/
private def renderStatus : BaselineStatus -> String
  | .pass => "pass"
  | .improvement => "improvement"
  | .regression => "regression"

/-- Render an optional string for text output. -/
private def renderOptionalText : Option String -> String
  | some value => value
  | none => "none"

/-- Render one finding identity as a stable text line. -/
private def renderFindingLine (finding : FindingIdentity) : String :=
  "- " ++ finding.declarationName ++
    " kind=" ++ finding.kind ++
    " category=" ++ finding.category ++
    " path=" ++ joinWith "." finding.path.toList ++
    " type=" ++ renderOptionalText finding.typeName?

/-- Render a finding section with deterministic ordering. -/
private def renderFindingSection (findings : Array FindingIdentity) : List String :=
  if findings.isEmpty then
    ["- none"]
  else
    findings.toList.map renderFindingLine

/-- Baseline-mode limitation line for human output. -/
private def limitationsText : String :=
  "limitations: compares rendered audit artifacts only; does not re-run Lean elaboration, " ++
    "validate proof axioms, sandbox execution, or change policy semantics."

/-- Render a complete baseline comparison as stable text. -/
def renderText (comparison : BaselineComparison) : String :=
  let lines := [
    "lean-assumptions baseline report",
    "tool_version: " ++ toolVersion,
    "lean_version: " ++ Lean.versionString,
    "schema_version: " ++ jsonSchemaVersion,
    "baseline_schema_version: " ++ comparison.baseline.metadata.schemaVersion,
    "baseline_lean_version: " ++ comparison.baseline.metadata.leanVersion,
    "current_lean_version: " ++ comparison.current.metadata.leanVersion,
    "current_schema_version: " ++ comparison.current.metadata.schemaVersion,
    "baseline_policy_identifier: " ++ comparison.baseline.metadata.policyIdentifier,
    "current_policy_identifier: " ++ comparison.current.metadata.policyIdentifier,
    "baseline_transparency_mode: " ++ comparison.baseline.metadata.transparencyMode,
    "current_transparency_mode: " ++ comparison.current.metadata.transparencyMode,
    "baseline_findings: " ++ toString comparison.baseline.findings.size,
    "current_findings: " ++ toString comparison.current.findings.size,
    "baseline_result: " ++ renderStatus comparison.status,
    "new_findings: " ++ toString comparison.addedFindings.size,
    "removed_findings: " ++ toString comparison.removedFindings.size,
    "new:"
  ] ++ renderFindingSection comparison.addedFindings ++
    ["removed:"] ++ renderFindingSection comparison.removedFindings ++
    [limitationsText]
  joinWith "\n" lines ++ "\n"

/-- Render a baseline update summary as stable text. -/
def renderUpdateText (path : System.FilePath) (current : AuditArtifact) : String :=
  let lines := [
    "lean-assumptions baseline report",
    "tool_version: " ++ toolVersion,
    "lean_version: " ++ Lean.versionString,
    "schema_version: " ++ jsonSchemaVersion,
    "baseline_path: " ++ path.toString,
    "current_schema_version: " ++ current.metadata.schemaVersion,
    "current_lean_version: " ++ current.metadata.leanVersion,
    "current_policy_identifier: " ++ current.metadata.policyIdentifier,
    "current_transparency_mode: " ++ current.metadata.transparencyMode,
    "current_findings: " ++ toString current.findings.size,
    "baseline_result: updated",
    limitationsText
  ]
  joinWith "\n" lines ++ "\n"

end LeanAssumptions.Baseline
