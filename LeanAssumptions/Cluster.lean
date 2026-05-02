import Lean.Data.Json.Parser
import LeanAssumptions.Version
import LeanAssumptions.JsonUtil

/-!
Support-layer failure clustering for rendered audit artifacts.

This module consumes JSON artifacts already emitted by `lean-assumptions`.
It does not inspect Lean environments, reclassify theorem surfaces, infer
project-specific cleanup lanes, or alter certified core or policy semantics.
-/

namespace LeanAssumptions.Cluster

/-- Metadata preserved from the source audit artifact. -/
structure SourceMetadata where
  schemaVersion : String
  leanVersion : String
  policyIdentifier : String
  transparencyMode : String
  declarations : Nat
  deriving BEq, Repr, Inhabited

/-- Parsed policy finding fields needed for deterministic clustering. -/
structure FindingSnapshot where
  kind : String
  severity : String
  category : String
  typeName? : Option String
  module? : Option String
  lane? : Option String
  deriving BEq, Repr, Inhabited

/-- Parsed declaration-level snapshot extracted from a JSON audit artifact. -/
structure DeclarationSnapshot where
  target : String
  policyResult : String
  findings : Array FindingSnapshot
  module? : Option String
  lane? : Option String
  deriving BEq, Repr, Inhabited

/-- Parsed single-report or batch audit artifact for clustering. -/
structure AuditArtifact where
  metadata : SourceMetadata
  declarations : Array DeclarationSnapshot
  deriving BEq, Repr, Inhabited

/-- Report-derived deterministic cluster signature. -/
structure ClusterKey where
  sourceClass : String
  findingKind : String
  category : String
  typeName? : Option String
  module? : Option String
  lane? : Option String
  deriving BEq, Repr, Inhabited

/-- One deterministic failure cluster. -/
structure FailureCluster where
  key : ClusterKey
  declarations : Array String
  findingCount : Nat
  deriving BEq, Repr, Inhabited

/-- Summary counts for a cluster report. -/
structure ClusterSummary where
  declarationsScanned : Nat
  failingDeclarations : Nat
  failureFindings : Nat
  clusters : Nat
  deriving BEq, Repr, Inhabited

/-- Complete deterministic failure-clustering report. -/
structure ClusterReport where
  source : SourceMetadata
  summary : ClusterSummary
  clusters : Array FailureCluster
  deriving BEq, Repr, Inhabited

/-- Join strings with a separator without depending on map iteration order. -/
private def joinWith (separator : String) : List String -> String
  | [] => ""
  | [item] => item
  | item :: rest => item ++ separator ++ joinWith separator rest

/-- Render a boolean using JSON-compatible spelling. -/
private def renderBool (value : Bool) : String :=
  if value then "true" else "false"

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

/-- Prefer the first optional value when it is present. -/
private def preferOption : Option α -> Option α -> Option α
  | some value, _ => some value
  | none, fallback => fallback

/-- Return whether a policy result is failing for cluster purposes. -/
private def policyResultIsFailure (result : String) : Bool :=
  result == "fail" || result == "audit_error"

/-- Return whether a policy-finding severity is failing for cluster purposes. -/
private def severityIsFailure (severity : String) : Bool :=
  severity == "failure" || severity == "audit_error"

/-- Derive the general source class from a public finding category. -/
private def sourceClassOfCategory (category : String) : String :=
  match category with
  | "direct_prop" => "direct_prop"
  | "package_with_prop_fields" => "package"
  | "proof_carrying_data" => "proof_carrying_data"
  | "typeclass_assumption" => "typeclass"
  | "alias" => "alias"
  | "unknown" => "unknown"
  | _ => "other"

/-- Parse one policy finding from a report object. -/
private def parseFinding
    (declarationModule? declarationLane? : Option String)
    (json : Lean.Json) : Except String FindingSnapshot := do
  let findingModule? ← optionalString json "module"
  let findingLane? ← optionalString json "lane"
  pure {
    kind := ← requiredString json "kind"
    severity := ← requiredString json "severity"
    category := ← requiredString json "category"
    typeName? := ← optionalString json "type_name"
    module? := preferOption findingModule? declarationModule?
    lane? := preferOption findingLane? declarationLane?
  }

/-- Parse one report object into a declaration snapshot. -/
private def parseDeclarationSnapshot (json : Lean.Json) : Except String DeclarationSnapshot := do
  let declarationModule? ← optionalString json "module"
  let declarationLane? ← optionalString json "lane"
  let findingJson ← (← json.getObjVal? "policy_findings").getArr?
  let findings ← findingJson.mapM (parseFinding declarationModule? declarationLane?)
  pure {
    target := ← requiredString json "target"
    policyResult := ← requiredString json "policy_result"
    findings := findings
    module? := declarationModule?
    lane? := declarationLane?
  }

/-- Insert a string into a deterministic sorted unique list. -/
private def insertSortedUnique (value : String) : List String -> List String
  | [] => [value]
  | head :: rest =>
    if value == head then
      head :: rest
    else if value < head then
      value :: head :: rest
    else
      head :: insertSortedUnique value rest

/-- Insert a declaration snapshot into target-name order. -/
private def insertSnapshot (snapshot : DeclarationSnapshot) : List DeclarationSnapshot ->
    List DeclarationSnapshot
  | [] => [snapshot]
  | head :: rest =>
    if snapshot.target < head.target then
      snapshot :: head :: rest
    else
      head :: insertSnapshot snapshot rest

/-- Sort declaration snapshots by stable target name. -/
private def sortSnapshots (snapshots : Array DeclarationSnapshot) : Array DeclarationSnapshot :=
  snapshots.foldl (fun sorted snapshot => insertSnapshot snapshot sorted) [] |>.toArray

/-- Return whether a sorted snapshot array contains duplicate targets. -/
private def hasDuplicateTargets : List DeclarationSnapshot -> Bool
  | [] => false
  | [_] => false
  | first :: second :: rest =>
    first.target == second.target || hasDuplicateTargets (second :: rest)

/-- Extract report objects from either a single-report artifact or a batch artifact. -/
private def reportObjects (json : Lean.Json) : Except String (Array Lean.Json) := do
  match ← optionalObjVal json "reports" with
  | some reports => reports.getArr?
  | none => pure #[json]

/-- Parse a single-report or batch JSON artifact for failure clustering. -/
def parseAuditArtifact (json : Lean.Json) : Except String AuditArtifact := do
  let reports ← reportObjects json
  let declarations ← reports.mapM parseDeclarationSnapshot
  let declarations := sortSnapshots declarations
  if hasDuplicateTargets declarations.toList then
    throw "cluster artifacts must not contain duplicate target declarations"
  pure {
    metadata := {
      schemaVersion := ← requiredString json "schema_version"
      leanVersion := ← requiredString json "lean_version"
      policyIdentifier := ← requiredString json "policy_identifier"
      transparencyMode := ← requiredString json "transparency_mode"
      declarations := declarations.size
    }
    declarations := declarations
  }

/-- Return failing findings from a parsed declaration. -/
private def failingFindings (declaration : DeclarationSnapshot) : Array FindingSnapshot :=
  declaration.findings.foldl (fun found finding =>
    if severityIsFailure finding.severity then found.push finding else found) #[]

/-- Conservative synthetic finding for malformed failing reports without failing findings. -/
private def missingFailureFinding (declaration : DeclarationSnapshot) : FindingSnapshot := {
  kind := "missing_failure_finding"
  severity := "audit_error"
  category := "unknown"
  typeName? := none
  module? := declaration.module?
  lane? := declaration.lane?
}

/-- Build the deterministic cluster key for one finding. -/
private def keyOfFinding (finding : FindingSnapshot) : ClusterKey := {
  sourceClass := sourceClassOfCategory finding.category
  findingKind := finding.kind
  category := finding.category
  typeName? := finding.typeName?
  module? := finding.module?
  lane? := finding.lane?
}

/-- Add a target to a sorted unique declaration array. -/
private def addDeclarationTarget (target : String) (declarations : Array String) : Array String :=
  insertSortedUnique target declarations.toList |>.toArray

/-- Add one failing finding to an existing list of clusters. -/
private def addFindingToClusters
    (target : String)
    (finding : FindingSnapshot) : List FailureCluster -> List FailureCluster
  | [] => [{
      key := keyOfFinding finding
      declarations := #[target]
      findingCount := 1
    }]
  | cluster :: rest =>
    let key := keyOfFinding finding
    if cluster.key == key then
      { cluster with
        declarations := addDeclarationTarget target cluster.declarations
        findingCount := cluster.findingCount + 1
      } :: rest
    else
      cluster :: addFindingToClusters target finding rest

/-- Add all failing findings for one failing declaration. -/
private def addDeclarationToClusters
    (clusters : List FailureCluster)
    (declaration : DeclarationSnapshot) : List FailureCluster :=
  if policyResultIsFailure declaration.policyResult then
    let findings := failingFindings declaration
    let findings :=
      if findings.isEmpty then
        #[missingFailureFinding declaration]
      else
        findings
    findings.foldl (fun clusters finding => addFindingToClusters declaration.target finding clusters)
      clusters
  else
    clusters

/-- Render an optional string into a stable sorting key. -/
private def optionKey : Option String -> String
  | some value => value
  | none => ""

/-- Render the cluster signature into a stable sorting key. -/
private def clusterSortKey (cluster : FailureCluster) : String :=
  joinWith "|" [
    cluster.key.sourceClass,
    cluster.key.findingKind,
    cluster.key.category,
    optionKey cluster.key.typeName?,
    optionKey cluster.key.module?,
    optionKey cluster.key.lane?
  ]

/-- Return whether one cluster sorts before another. -/
private def clusterLt (left right : FailureCluster) : Bool :=
  if left.declarations.size > right.declarations.size then
    true
  else if left.declarations.size < right.declarations.size then
    false
  else
    clusterSortKey left < clusterSortKey right

/-- Insert a cluster into the deterministic final ordering. -/
private def insertCluster (cluster : FailureCluster) : List FailureCluster -> List FailureCluster
  | [] => [cluster]
  | head :: rest =>
    if clusterLt cluster head then
      cluster :: head :: rest
    else
      head :: insertCluster cluster rest

/-- Sort clusters by descending declaration count, then signature. -/
private def sortClusters (clusters : List FailureCluster) : Array FailureCluster :=
  clusters.foldl (fun sorted cluster => insertCluster cluster sorted) [] |>.toArray

/-- Count failing declarations in an artifact. -/
private def countFailingDeclarations (declarations : Array DeclarationSnapshot) : Nat :=
  declarations.foldl (fun count declaration =>
    if policyResultIsFailure declaration.policyResult then count + 1 else count) 0

/-- Count clustered failing findings. -/
private def countClusteredFindings (clusters : Array FailureCluster) : Nat :=
  clusters.foldl (fun count cluster => count + cluster.findingCount) 0

/-- Build a deterministic failure-clustering report from a parsed artifact. -/
def clusterArtifact (artifact : AuditArtifact) : ClusterReport :=
  let clusters :=
    artifact.declarations.foldl addDeclarationToClusters [] |> sortClusters
  let failureFindings := countClusteredFindings clusters
  {
    source := artifact.metadata
    summary := {
      declarationsScanned := artifact.declarations.size
      failingDeclarations := countFailingDeclarations artifact.declarations
      failureFindings := failureFindings
      clusters := clusters.size
    }
    clusters := clusters
  }

/-- Parse and cluster one JSON artifact. -/
def clusterJsonArtifact (json : Lean.Json) : Except String ClusterReport := do
  let artifact ← parseAuditArtifact json
  pure (clusterArtifact artifact)

/-- Read a JSON artifact and cluster its failing declarations. -/
def readClusterReport (path : System.FilePath) : IO ClusterReport := do
  let text ← IO.FS.readFile path
  let json ←
    match Lean.Json.parse text with
    | .ok json => pure json
    | .error error => throw (IO.userError s!"invalid cluster JSON: {error}")
  match clusterJsonArtifact json with
  | .ok report => pure report
  | .error error => throw (IO.userError error)

/-- Render an optional string for text output. -/
private def renderOptionalText : Option String -> String
  | some value => value
  | none => "none"

/-- Render a string array as compact stable text. -/
private def renderStringArrayText (values : Array String) : String :=
  "[" ++ joinWith "," values.toList ++ "]"

/-- Render one failure cluster as stable text lines. -/
private def renderClusterTextLines (cluster : FailureCluster) : List String := [
  "- source=" ++ cluster.key.sourceClass ++
    " kind=" ++ cluster.key.findingKind ++
    " category=" ++ cluster.key.category ++
    " type=" ++ renderOptionalText cluster.key.typeName? ++
    " module=" ++ renderOptionalText cluster.key.module? ++
    " lane=" ++ renderOptionalText cluster.key.lane? ++
    " declarations=" ++ toString cluster.declarations.size ++
    " findings=" ++ toString cluster.findingCount,
  "  declarations: " ++ renderStringArrayText cluster.declarations
]

/-- Limitation line shared by human cluster output. -/
private def limitationsText : String :=
  "limitations: clusters rendered audit artifacts only; does not re-run Lean elaboration, " ++
    "validate proof axioms, sandbox execution, prove theorem-statement equivalence, " ++
    "infer project-specific cleanup lanes, or suggest remediation."

/-- Render a complete cluster report as stable human-readable text. -/
def renderText (report : ClusterReport) : String :=
  let clusterLines :=
    if report.clusters.isEmpty then
      ["- none"]
    else
      report.clusters.toList.foldl (fun lines cluster => lines ++ renderClusterTextLines cluster) []
  let lines := [
    "lean-assumptions cluster report",
    "tool_version: " ++ toolVersion,
    "schema_version: " ++ jsonSchemaVersion,
    "source_schema_version: " ++ report.source.schemaVersion,
    "source_lean_version: " ++ report.source.leanVersion,
    "source_policy_identifier: " ++ report.source.policyIdentifier,
    "source_transparency_mode: " ++ report.source.transparencyMode,
    "declarations_scanned: " ++ toString report.summary.declarationsScanned,
    "failing_declarations: " ++ toString report.summary.failingDeclarations,
    "failure_findings: " ++ toString report.summary.failureFindings,
    "clusters: " ++ toString report.summary.clusters,
    "failure_clusters:"
  ] ++ clusterLines ++ [limitationsText]
  joinWith "\n" lines ++ "\n"

/-- Quote a JSON string. -/
private def jsonString (value : String) : String :=
  LeanAssumptions.JsonUtil.quoteString value

/-- Render an optional string as JSON. -/
private def jsonOptionalString : Option String -> String
  | some value => jsonString value
  | none => "null"

/-- Render a JSON array from already-rendered JSON items. -/
private def jsonArray (items : Array String) : String :=
  "[" ++ joinWith "," items.toList ++ "]"

/-- Render a JSON object from already-rendered key/value fields. -/
private def jsonObject (fields : List (Prod String String)) : String :=
  "{" ++ joinWith "," (fields.map fun field => jsonString field.fst ++ ":" ++ field.snd) ++ "}"

/-- Render source metadata as deterministic JSON. -/
private def renderSourceJson (source : SourceMetadata) : String :=
  jsonObject [
    ("schema_version", jsonString source.schemaVersion),
    ("lean_version", jsonString source.leanVersion),
    ("policy_identifier", jsonString source.policyIdentifier),
    ("transparency_mode", jsonString source.transparencyMode),
    ("declarations", toString source.declarations)
  ]

/-- Render summary counts as deterministic JSON. -/
private def renderSummaryJson (summary : ClusterSummary) : String :=
  jsonObject [
    ("declarations_scanned", toString summary.declarationsScanned),
    ("failing_declarations", toString summary.failingDeclarations),
    ("failure_findings", toString summary.failureFindings),
    ("clusters", toString summary.clusters)
  ]

/-- Render one failure cluster as deterministic JSON. -/
private def renderClusterJson (cluster : FailureCluster) : String :=
  jsonObject [
    ("source_class", jsonString cluster.key.sourceClass),
    ("finding_kind", jsonString cluster.key.findingKind),
    ("category", jsonString cluster.key.category),
    ("type_name", jsonOptionalString cluster.key.typeName?),
    ("module", jsonOptionalString cluster.key.module?),
    ("lane", jsonOptionalString cluster.key.lane?),
    ("declaration_count", toString cluster.declarations.size),
    ("finding_count", toString cluster.findingCount),
    ("declarations", jsonArray (cluster.declarations.map jsonString))
  ]

/-- Render a complete cluster report as stable minified JSON plus a trailing newline. -/
def renderJsonString (report : ClusterReport) : String :=
  jsonObject [
    ("schema_version", jsonString jsonSchemaVersion),
    ("tool_version", jsonString toolVersion),
    ("cluster_model_version", jsonString reportModelVersion),
    ("source", renderSourceJson report.source),
    ("summary", renderSummaryJson report.summary),
    ("clusters", jsonArray (report.clusters.map renderClusterJson)),
    ("limitations", jsonArray #[
      jsonString "clusters rendered audit artifacts only",
      jsonString "does not re-run Lean elaboration",
      jsonString "does not validate proof axioms",
      jsonString "does not sandbox Lean execution",
      jsonString "does not prove theorem-statement equivalence",
      jsonString "does not infer project-specific cleanup lanes",
      jsonString "does not suggest remediation"
    ])
  ] ++ "\n"

end LeanAssumptions.Cluster
