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

/--
FR-018 remediation signal for one failing declaration, inferred mechanically
from public finding categories: `hidden` failures come from packaging,
proof-carrying data, aliases, or unknowns; `explicit` failures from direct
proposition binders or typeclass assumptions; declarations with more than one
bucket are `mixed`.
-/
inductive RemediationSignal where
  | hidden
  | explicitDirectProp
  | explicitTypeclass
  | mixed
  deriving BEq, DecidableEq, Repr, Inhabited

/-- One report-derived failure family: a type head and its declaration count. -/
structure TrendFamily where
  typeName? : Option String
  declarations : Nat
  deriving BEq, Repr, Inhabited

/-- FR-019 deterministic trend summary derived from public artifact fields. -/
structure TrendSummary where
  hidden : Nat := 0
  explicitDirectProp : Nat := 0
  explicitTypeclass : Nat := 0
  mixed : Nat := 0
  hiddenFamilies : Array TrendFamily := #[]
  explicitDirectPropFamilies : Array TrendFamily := #[]
  laneCounts : Array (String × Nat) := #[]
  deriving BEq, Repr, Inhabited

/-- Complete deterministic failure-clustering report. -/
structure ClusterReport where
  source : SourceMetadata
  summary : ClusterSummary
  clusters : Array FailureCluster
  trend : TrendSummary
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

/-- The public policy-result spellings this schema version defines. -/
private def knownPolicyResults : List String :=
  ["pass", "warn", "fail", "audit_error"]

/-- The public finding-severity spellings this schema version defines. -/
private def knownSeverities : List String :=
  ["warning", "failure", "audit_error"]

/--
Require a recognized spelling for a policy-relevant enumeration field.

An unrecognized spelling must be a hard parse error: silently treating it as
non-failing would let a malformed or future-versioned artifact drop failing
declarations from the clustering.
-/
private def requireKnownSpelling
    (field : String) (known : List String) (value : String) : Except String String :=
  if known.contains value then
    pure value
  else
    throw s!"unrecognized {field} spelling in artifact: {value}"

/-- Parse one policy finding from a report object. -/
private def parseFinding
    (declarationModule? declarationLane? : Option String)
    (json : Lean.Json) : Except String FindingSnapshot := do
  let findingModule? ← optionalString json "module"
  let findingLane? ← optionalString json "lane"
  pure {
    kind := ← requiredString json "kind"
    severity := ← requireKnownSpelling "severity" knownSeverities
      (← requiredString json "severity")
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
    policyResult := ← requireKnownSpelling "policy_result" knownPolicyResults
      (← requiredString json "policy_result")
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
  let schemaVersion ← requiredString json "schema_version"
  if schemaVersion != "1" then
    throw s!"unsupported artifact schema_version for clustering: {schemaVersion}"
  pure {
    metadata := {
      schemaVersion := schemaVersion
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

/-- Return whether a finding category belongs to the hidden remediation bucket. -/
private def categoryIsHidden (category : String) : Bool :=
  category == "package_with_prop_fields" || category == "proof_carrying_data" ||
    category == "alias" || category == "unknown"

/--
Classify one failing declaration's remediation signal from the categories of
its failing findings (FR-018). Categories outside the public set are treated
as hidden, conservatively: content the report cannot name explicitly is not
explicit.
-/
def remediationSignalOfCategories (categories : Array String) : RemediationSignal :=
  let hasHidden := categories.any fun category =>
    !(category == "direct_prop" || category == "typeclass_assumption")
  let hasDirect := categories.any (· == "direct_prop")
  let hasTypeclass := categories.any (· == "typeclass_assumption")
  match hasHidden, hasDirect, hasTypeclass with
  | true, false, false => .hidden
  | false, true, false => .explicitDirectProp
  | false, false, true => .explicitTypeclass
  | _, _, _ => .mixed

/-- The remediation signal of one failing declaration snapshot. -/
private def signalOfDeclaration (declaration : DeclarationSnapshot) : RemediationSignal :=
  let findings := failingFindings declaration
  let findings := if findings.isEmpty then #[missingFailureFinding declaration] else findings
  remediationSignalOfCategories (findings.map (·.category))

/-- Insert one declaration into a sorted unique family count list. -/
private def addToFamilies (typeName? : Option String) :
    List TrendFamily -> List TrendFamily
  | [] => [{ typeName? := typeName?, declarations := 1 }]
  | family :: rest =>
    if family.typeName? == typeName? then
      { family with declarations := family.declarations + 1 } :: rest
    else
      family :: addToFamilies typeName? rest

/-- Sort families by descending declaration count, then type name. -/
private def sortFamilies (families : List TrendFamily) : Array TrendFamily :=
  let familyLt (left right : TrendFamily) : Bool :=
    if left.declarations > right.declarations then true
    else if left.declarations < right.declarations then false
    else optionKey left.typeName? < optionKey right.typeName?
  let rec insert (family : TrendFamily) : List TrendFamily -> List TrendFamily
    | [] => [family]
    | head :: rest =>
      if familyLt family head then family :: head :: rest else head :: insert family rest
  families.foldl (fun sorted family => insert family sorted) [] |>.toArray

/-- The first failing-finding type head per bucket for one declaration. -/
private def bucketTypeName? (declaration : DeclarationSnapshot)
    (bucket : String → Bool) : Option (Option String) :=
  let findings := failingFindings declaration
  let findings := if findings.isEmpty then #[missingFailureFinding declaration] else findings
  findings.foldl (fun found finding =>
    match found with
    | some _ => found
    | none => if bucket finding.category then some finding.typeName? else none) none

/-- Insert one lane occurrence into a sorted lane-count list. -/
private def addLaneCount (lane : String) : List (String × Nat) -> List (String × Nat)
  | [] => [(lane, 1)]
  | (name, count) :: rest =>
    if name == lane then (name, count + 1) :: rest
    else if lane < name then (lane, 1) :: (name, count) :: rest
    else (name, count) :: addLaneCount lane rest

/-- Compute the FR-019 trend summary over failing declarations. -/
private def trendOfDeclarations (declarations : Array DeclarationSnapshot) : TrendSummary :=
  declarations.foldl (fun trend declaration =>
    if !policyResultIsFailure declaration.policyResult then trend else
    let signal := signalOfDeclaration declaration
    let trend :=
      match signal with
      | .hidden => { trend with hidden := trend.hidden + 1 }
      | .explicitDirectProp =>
        { trend with explicitDirectProp := trend.explicitDirectProp + 1 }
      | .explicitTypeclass =>
        { trend with explicitTypeclass := trend.explicitTypeclass + 1 }
      | .mixed => { trend with mixed := trend.mixed + 1 }
    let trend :=
      match bucketTypeName? declaration categoryIsHidden with
      | some typeName? =>
        { trend with
          hiddenFamilies := (addToFamilies typeName? trend.hiddenFamilies.toList).toArray }
      | none => trend
    let trend :=
      match bucketTypeName? declaration (· == "direct_prop") with
      | some typeName? =>
        { trend with
          explicitDirectPropFamilies :=
            (addToFamilies typeName? trend.explicitDirectPropFamilies.toList).toArray }
      | none => trend
    match declaration.lane? with
    | some lane =>
      { trend with laneCounts := (addLaneCount lane trend.laneCounts.toList).toArray }
    | none => trend) {}

/-- Sort the family lists of a computed trend deterministically. -/
private def sortTrend (trend : TrendSummary) : TrendSummary := {
  trend with
  hiddenFamilies := sortFamilies trend.hiddenFamilies.toList
  explicitDirectPropFamilies := sortFamilies trend.explicitDirectPropFamilies.toList
}

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
    trend := sortTrend (trendOfDeclarations artifact.declarations)
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

/-- Render one trend family as a stable text fragment. -/
private def renderFamilyText (family : TrendFamily) : String :=
  renderOptionalText family.typeName? ++ "=" ++ toString family.declarations

/-- Render a trend family list as stable text. -/
private def renderFamiliesText (families : Array TrendFamily) : String :=
  if families.isEmpty then
    "none"
  else
    joinWith "," (families.toList.map renderFamilyText)

/-- Render lane counts as stable text. -/
private def renderLaneCountsText (lanes : Array (String × Nat)) : String :=
  if lanes.isEmpty then
    "none"
  else
    joinWith "," (lanes.toList.map fun (lane, count) => lane ++ "=" ++ toString count)

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
    "trend_hidden: " ++ toString report.trend.hidden,
    "trend_explicit_direct_prop: " ++ toString report.trend.explicitDirectProp,
    "trend_explicit_typeclass: " ++ toString report.trend.explicitTypeclass,
    "trend_mixed: " ++ toString report.trend.mixed,
    "trend_hidden_families: " ++ renderFamiliesText report.trend.hiddenFamilies,
    "trend_explicit_direct_prop_families: " ++
      renderFamiliesText report.trend.explicitDirectPropFamilies,
    "trend_lanes: " ++ renderLaneCountsText report.trend.laneCounts,
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

/-- Render one trend family as deterministic JSON. -/
private def renderFamilyJson (family : TrendFamily) : String :=
  jsonObject [
    ("type_name", jsonOptionalString family.typeName?),
    ("declarations", toString family.declarations)
  ]

/-- Render lane counts as deterministic JSON. -/
private def renderLaneCountJson (lane : String × Nat) : String :=
  jsonObject [
    ("lane", jsonString lane.fst),
    ("declarations", toString lane.snd)
  ]

/-- Render the FR-019 trend summary as deterministic JSON. -/
private def renderTrendJson (trend : TrendSummary) : String :=
  jsonObject [
    ("hidden", toString trend.hidden),
    ("explicit_direct_prop", toString trend.explicitDirectProp),
    ("explicit_typeclass", toString trend.explicitTypeclass),
    ("mixed", toString trend.mixed),
    ("hidden_families", jsonArray (trend.hiddenFamilies.map renderFamilyJson)),
    ("explicit_direct_prop_families",
      jsonArray (trend.explicitDirectPropFamilies.map renderFamilyJson)),
    ("lanes", jsonArray (trend.laneCounts.map renderLaneCountJson))
  ]

/-- Render a complete cluster report as stable minified JSON plus a trailing newline. -/
def renderJsonString (report : ClusterReport) : String :=
  jsonObject [
    ("schema_version", jsonString jsonSchemaVersion),
    ("tool_version", jsonString toolVersion),
    ("cluster_model_version", jsonString reportModelVersion),
    ("source", renderSourceJson report.source),
    ("summary", renderSummaryJson report.summary),
    ("trend", renderTrendJson report.trend),
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
