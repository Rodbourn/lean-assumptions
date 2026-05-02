import Lean.Data.Json.Parser
import LeanAssumptions.Version

/-!
Support-layer delta reporting for rendered audit artifacts.

This module compares JSON artifacts already emitted by `lean-assumptions`.
It does not inspect Lean environments, reclassify theorem surfaces, or alter
certified core or policy semantics.
-/

namespace LeanAssumptions.Delta

/-- Role of an artifact in a two-way delta comparison. -/
inductive ArtifactRole where
  | baseline
  | current
  deriving BEq, DecidableEq, Repr, Inhabited

/-- Top-level boundary node shape used for FR-016 comparisons. -/
structure BoundaryNode where
  name : String
  binderKind : String
  primaryCategory : String
  binderTypeRepr : String
  deriving BEq, Repr, Inhabited

/-- Parsed declaration-level snapshot extracted from a JSON audit artifact. -/
structure DeclarationSnapshot where
  target : String
  policyResult : String
  findingCategories : Array String
  boundaryShape : Array BoundaryNode
  deriving BEq, Repr, Inhabited

/-- Metadata preserved from one side of a delta comparison. -/
structure ArtifactMetadata where
  artifactRole : ArtifactRole
  schemaVersion : String
  leanVersion : String
  policyIdentifier : String
  transparencyMode : String
  declarations : Nat
  deriving BEq, Repr, Inhabited

/-- Parsed single-report or batch audit artifact. -/
structure AuditArtifact where
  metadata : ArtifactMetadata
  declarations : Array DeclarationSnapshot
  deriving BEq, Repr, Inhabited

/-- Public change kinds emitted by delta reports. -/
inductive ChangeKind where
  | added
  | removed
  | changed
  deriving BEq, DecidableEq, Repr, Inhabited

/-- One declaration-level delta entry. -/
structure DeclarationDelta where
  target : String
  changeKind : ChangeKind
  baselinePolicyResult? : Option String
  currentPolicyResult? : Option String
  policyResultChanged : Bool
  baselineFindingCategories : Array String
  currentFindingCategories : Array String
  findingCategoriesChanged : Bool
  baselineBoundaryShape : Array BoundaryNode
  currentBoundaryShape : Array BoundaryNode
  boundaryShapeChanged : Bool
  deriving BEq, Repr, Inhabited

/-- Summary counts for a delta report. -/
structure DeltaSummary where
  baselineDeclarations : Nat
  currentDeclarations : Nat
  declarationsAdded : Nat
  declarationsRemoved : Nat
  declarationsChanged : Nat
  policyResultChanged : Nat
  findingCategoriesChanged : Nat
  boundaryShapeChanged : Nat
  deriving BEq, Repr, Inhabited

/-- Complete deterministic delta report. -/
structure DeltaReport where
  baseline : ArtifactMetadata
  current : ArtifactMetadata
  summary : DeltaSummary
  changes : Array DeclarationDelta
  deriving BEq, Repr, Inhabited

/-- Join strings with a separator without depending on map iteration order. -/
private def joinWith (separator : String) : List String -> String
  | [] => ""
  | [item] => item
  | item :: rest => item ++ separator ++ joinWith separator rest

/-- Render a boolean using JSON-compatible spelling. -/
private def renderBool (value : Bool) : String :=
  if value then "true" else "false"

/-- Map and concatenate a list deterministically. -/
private def concatMap (f : α -> List β) : List α -> List β
  | [] => []
  | item :: rest => f item ++ concatMap f rest

/-- Render an artifact role using schema spelling. -/
private def renderArtifactRole : ArtifactRole -> String
  | .baseline => "baseline"
  | .current => "current"

/-- Render a change kind using schema spelling. -/
private def renderChangeKind : ChangeKind -> String
  | .added => "added"
  | .removed => "removed"
  | .changed => "changed"

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

/-- Sort strings deterministically and drop duplicates. -/
private def sortUniqueStrings (values : Array String) : Array String :=
  values.foldl (fun sorted value => insertSortedUnique value sorted) [] |>.toArray

/-- Return an optional object field from a JSON object. -/
private def optionalObjVal (json : Lean.Json) (key : String) : Except String (Option Lean.Json) :=
  match json.getObjVal? key with
  | .ok value => .ok (some value)
  | .error _ => .ok none

/-- Read a required JSON string field. -/
private def requiredString (json : Lean.Json) (key : String) : Except String String := do
  (← json.getObjVal? key).getStr?

/-- Parse one top-level boundary node from a report's assumption tree. -/
private def parseBoundaryNode (json : Lean.Json) : Except String BoundaryNode := do
  pure {
    name := ← requiredString json "name"
    binderKind := ← requiredString json "binder_kind"
    primaryCategory := ← requiredString json "primary_category"
    binderTypeRepr := ← requiredString json "binder_type_repr"
  }

/-- Parse the sorted unique policy-finding category set from a report. -/
private def parseFindingCategories (json : Lean.Json) : Except String (Array String) := do
  let findings ← (← json.getObjVal? "policy_findings").getArr?
  let categories ← findings.mapM fun finding => requiredString finding "category"
  pure (sortUniqueStrings categories)

/-- Parse the top-level boundary shape from a report assumption tree. -/
private def parseBoundaryShape (json : Lean.Json) : Except String (Array BoundaryNode) := do
  let nodes ← (← json.getObjVal? "assumption_tree").getArr?
  nodes.mapM parseBoundaryNode

/-- Parse one report object into a declaration snapshot. -/
private def parseDeclarationSnapshot (json : Lean.Json) : Except String DeclarationSnapshot := do
  pure {
    target := ← requiredString json "target"
    policyResult := ← requiredString json "policy_result"
    findingCategories := ← parseFindingCategories json
    boundaryShape := ← parseBoundaryShape json
  }

/-- Return whether a sorted snapshot array contains duplicate targets. -/
private def hasDuplicateTargets : List DeclarationSnapshot -> Bool
  | [] => false
  | [_] => false
  | first :: second :: rest =>
    first.target == second.target || hasDuplicateTargets (second :: rest)

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

/-- Extract report objects from either a single-report artifact or a batch artifact. -/
private def reportObjects (json : Lean.Json) : Except String (Array Lean.Json) := do
  match ← optionalObjVal json "reports" with
  | some reports => reports.getArr?
  | none => pure #[json]

/-- Parse a single-report or batch JSON artifact for delta comparison. -/
def parseAuditArtifact (role : ArtifactRole) (json : Lean.Json) : Except String AuditArtifact := do
  let reports ← reportObjects json
  let declarations ← reports.mapM parseDeclarationSnapshot
  let declarations := sortSnapshots declarations
  if hasDuplicateTargets declarations.toList then
    throw "delta artifacts must not contain duplicate target declarations"
  pure {
    metadata := {
      artifactRole := role
      schemaVersion := ← requiredString json "schema_version"
      leanVersion := ← requiredString json "lean_version"
      policyIdentifier := ← requiredString json "policy_identifier"
      transparencyMode := ← requiredString json "transparency_mode"
      declarations := declarations.size
    }
    declarations := declarations
  }

/-- Build an added-declaration delta entry. -/
private def addedDelta (current : DeclarationSnapshot) : DeclarationDelta := {
  target := current.target
  changeKind := .added
  baselinePolicyResult? := none
  currentPolicyResult? := some current.policyResult
  policyResultChanged := false
  baselineFindingCategories := #[]
  currentFindingCategories := current.findingCategories
  findingCategoriesChanged := false
  baselineBoundaryShape := #[]
  currentBoundaryShape := current.boundaryShape
  boundaryShapeChanged := false
}

/-- Build a removed-declaration delta entry. -/
private def removedDelta (baseline : DeclarationSnapshot) : DeclarationDelta := {
  target := baseline.target
  changeKind := .removed
  baselinePolicyResult? := some baseline.policyResult
  currentPolicyResult? := none
  policyResultChanged := false
  baselineFindingCategories := baseline.findingCategories
  currentFindingCategories := #[]
  findingCategoriesChanged := false
  baselineBoundaryShape := baseline.boundaryShape
  currentBoundaryShape := #[]
  boundaryShapeChanged := false
}

/-- Build a changed-declaration delta entry if any FR-016 comparison changed. -/
private def changedDelta? (baseline current : DeclarationSnapshot) : Option DeclarationDelta :=
  let policyResultChanged := baseline.policyResult != current.policyResult
  let findingCategoriesChanged := baseline.findingCategories != current.findingCategories
  let boundaryShapeChanged := baseline.boundaryShape != current.boundaryShape
  if policyResultChanged || findingCategoriesChanged || boundaryShapeChanged then
    some {
      target := baseline.target
      changeKind := .changed
      baselinePolicyResult? := some baseline.policyResult
      currentPolicyResult? := some current.policyResult
      policyResultChanged := policyResultChanged
      baselineFindingCategories := baseline.findingCategories
      currentFindingCategories := current.findingCategories
      findingCategoriesChanged := findingCategoriesChanged
      baselineBoundaryShape := baseline.boundaryShape
      currentBoundaryShape := current.boundaryShape
      boundaryShapeChanged := boundaryShapeChanged
    }
  else
    none

/-- Merge sorted declaration snapshots into deterministic delta entries. -/
private def compareSnapshots :
    List DeclarationSnapshot -> List DeclarationSnapshot -> List DeclarationDelta
  | [], [] => []
  | [], current :: currentRest => addedDelta current :: compareSnapshots [] currentRest
  | baseline :: baselineRest, [] => removedDelta baseline :: compareSnapshots baselineRest []
  | baseline :: baselineRest, current :: currentRest =>
    if baseline.target == current.target then
      match changedDelta? baseline current with
      | some delta => delta :: compareSnapshots baselineRest currentRest
      | none => compareSnapshots baselineRest currentRest
    else if baseline.target < current.target then
      removedDelta baseline :: compareSnapshots baselineRest (current :: currentRest)
    else
      addedDelta current :: compareSnapshots (baseline :: baselineRest) currentRest

/-- Compute summary counts for deterministic delta entries. -/
private def summarizeDeltas
    (baselineDeclarations currentDeclarations : Nat)
    (changes : Array DeclarationDelta) : DeltaSummary := {
  baselineDeclarations := baselineDeclarations
  currentDeclarations := currentDeclarations
  declarationsAdded := changes.foldl (fun count change =>
    if change.changeKind == .added then count + 1 else count) 0
  declarationsRemoved := changes.foldl (fun count change =>
    if change.changeKind == .removed then count + 1 else count) 0
  declarationsChanged := changes.foldl (fun count change =>
    if change.changeKind == .changed then count + 1 else count) 0
  policyResultChanged := changes.foldl (fun count change =>
    if change.policyResultChanged then count + 1 else count) 0
  findingCategoriesChanged := changes.foldl (fun count change =>
    if change.findingCategoriesChanged then count + 1 else count) 0
  boundaryShapeChanged := changes.foldl (fun count change =>
    if change.boundaryShapeChanged then count + 1 else count) 0
}

/-- Compare two parsed audit artifacts into a deterministic delta report. -/
def compareArtifacts (baseline current : AuditArtifact) : DeltaReport :=
  let changes := compareSnapshots baseline.declarations.toList current.declarations.toList |>.toArray
  {
    baseline := baseline.metadata
    current := current.metadata
    summary := summarizeDeltas baseline.declarations.size current.declarations.size changes
    changes := changes
  }

/-- Parse and compare two JSON values into a deterministic delta report. -/
def compareJsonArtifacts (baselineJson currentJson : Lean.Json) : Except String DeltaReport := do
  let baseline ← parseAuditArtifact .baseline baselineJson
  let current ← parseAuditArtifact .current currentJson
  pure (compareArtifacts baseline current)

/-- Read two JSON files and compare them into a deterministic delta report. -/
def readDeltaReport (baselinePath currentPath : System.FilePath) : IO DeltaReport := do
  let baselineText ← IO.FS.readFile baselinePath
  let currentText ← IO.FS.readFile currentPath
  let baselineJson ←
    match Lean.Json.parse baselineText with
    | .ok json => pure json
    | .error error => throw (IO.userError s!"invalid baseline JSON: {error}")
  let currentJson ←
    match Lean.Json.parse currentText with
    | .ok json => pure json
    | .error error => throw (IO.userError s!"invalid current JSON: {error}")
  match compareJsonArtifacts baselineJson currentJson with
  | .ok report => pure report
  | .error error => throw (IO.userError error)

/-- Render an optional string for text output. -/
private def renderOptionalText : Option String -> String
  | some value => value
  | none => "none"

/-- Render a sorted string array as compact stable text. -/
private def renderStringArrayText (values : Array String) : String :=
  "[" ++ joinWith "," values.toList ++ "]"

/-- Render one boundary node in compact stable text. -/
private def renderBoundaryNodeText (node : BoundaryNode) : String :=
  node.name ++ "|" ++ node.binderKind ++ "|" ++ node.primaryCategory ++ "|" ++ node.binderTypeRepr

/-- Render a top-level boundary-shape array as compact stable text. -/
private def renderBoundaryShapeText (nodes : Array BoundaryNode) : String :=
  "[" ++ joinWith "," (nodes.toList.map renderBoundaryNodeText) ++ "]"

/-- Render one declaration delta as stable text lines. -/
private def renderDeltaTextLines (delta : DeclarationDelta) : List String := [
  "- " ++ delta.target ++ " kind=" ++ renderChangeKind delta.changeKind,
  "  baseline_policy_result: " ++ renderOptionalText delta.baselinePolicyResult?,
  "  current_policy_result: " ++ renderOptionalText delta.currentPolicyResult?,
  "  policy_result_changed: " ++ renderBool delta.policyResultChanged,
  "  baseline_finding_categories: " ++ renderStringArrayText delta.baselineFindingCategories,
  "  current_finding_categories: " ++ renderStringArrayText delta.currentFindingCategories,
  "  finding_categories_changed: " ++ renderBool delta.findingCategoriesChanged,
  "  baseline_boundary_shape: " ++ renderBoundaryShapeText delta.baselineBoundaryShape,
  "  current_boundary_shape: " ++ renderBoundaryShapeText delta.currentBoundaryShape,
  "  boundary_shape_changed: " ++ renderBool delta.boundaryShapeChanged
]

/-- Limitation line shared by human delta output. -/
private def limitationsText : String :=
  "limitations: compares rendered audit artifacts only; does not re-run Lean elaboration, " ++
    "validate proof axioms, sandbox execution, prove theorem-statement equivalence, or suggest remediation."

/-- Render a complete delta report as stable human-readable text. -/
def renderText (report : DeltaReport) : String :=
  let changeLines :=
    if report.changes.isEmpty then
      ["- none"]
    else
      concatMap renderDeltaTextLines report.changes.toList
  let lines := [
    "lean-assumptions delta report",
    "tool_version: " ++ toolVersion,
    "schema_version: " ++ jsonSchemaVersion,
    "baseline_schema_version: " ++ report.baseline.schemaVersion,
    "current_schema_version: " ++ report.current.schemaVersion,
    "baseline_lean_version: " ++ report.baseline.leanVersion,
    "current_lean_version: " ++ report.current.leanVersion,
    "baseline_policy_identifier: " ++ report.baseline.policyIdentifier,
    "current_policy_identifier: " ++ report.current.policyIdentifier,
    "baseline_transparency_mode: " ++ report.baseline.transparencyMode,
    "current_transparency_mode: " ++ report.current.transparencyMode,
    "baseline_declarations: " ++ toString report.summary.baselineDeclarations,
    "current_declarations: " ++ toString report.summary.currentDeclarations,
    "summary:",
    "declarations_added: " ++ toString report.summary.declarationsAdded,
    "declarations_removed: " ++ toString report.summary.declarationsRemoved,
    "declarations_changed: " ++ toString report.summary.declarationsChanged,
    "policy_result_changed: " ++ toString report.summary.policyResultChanged,
    "finding_categories_changed: " ++ toString report.summary.findingCategoriesChanged,
    "boundary_shape_changed: " ++ toString report.summary.boundaryShapeChanged,
    "changes:"
  ] ++ changeLines ++ [limitationsText]
  joinWith "\n" lines ++ "\n"

/-- Escape a string for deterministic JSON output. -/
private def jsonEscape (value : String) : String :=
  value.foldl (init := "") fun acc char =>
    match char with
    | '"' => acc ++ "\\\""
    | '\\' => acc ++ "\\\\"
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | _ => acc.push char

/-- Quote a JSON string. -/
private def jsonString (value : String) : String :=
  "\"" ++ jsonEscape value ++ "\""

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

/-- Render artifact metadata as deterministic JSON. -/
private def renderArtifactMetadataJson (metadata : ArtifactMetadata) : String :=
  jsonObject [
    ("artifact_role", jsonString (renderArtifactRole metadata.artifactRole)),
    ("schema_version", jsonString metadata.schemaVersion),
    ("lean_version", jsonString metadata.leanVersion),
    ("policy_identifier", jsonString metadata.policyIdentifier),
    ("transparency_mode", jsonString metadata.transparencyMode),
    ("declarations", toString metadata.declarations)
  ]

/-- Render summary counts as deterministic JSON. -/
private def renderSummaryJson (summary : DeltaSummary) : String :=
  jsonObject [
    ("baseline_declarations", toString summary.baselineDeclarations),
    ("current_declarations", toString summary.currentDeclarations),
    ("declarations_added", toString summary.declarationsAdded),
    ("declarations_removed", toString summary.declarationsRemoved),
    ("declarations_changed", toString summary.declarationsChanged),
    ("policy_result_changed", toString summary.policyResultChanged),
    ("finding_categories_changed", toString summary.findingCategoriesChanged),
    ("boundary_shape_changed", toString summary.boundaryShapeChanged)
  ]

/-- Render one boundary node as deterministic JSON. -/
private def renderBoundaryNodeJson (node : BoundaryNode) : String :=
  jsonObject [
    ("name", jsonString node.name),
    ("binder_kind", jsonString node.binderKind),
    ("primary_category", jsonString node.primaryCategory),
    ("binder_type_repr", jsonString node.binderTypeRepr)
  ]

/-- Render one declaration delta as deterministic JSON. -/
private def renderDeclarationDeltaJson (delta : DeclarationDelta) : String :=
  jsonObject [
    ("target", jsonString delta.target),
    ("change_kind", jsonString (renderChangeKind delta.changeKind)),
    ("baseline_policy_result", jsonOptionalString delta.baselinePolicyResult?),
    ("current_policy_result", jsonOptionalString delta.currentPolicyResult?),
    ("policy_result_changed", renderBool delta.policyResultChanged),
    ("baseline_finding_categories", jsonArray (delta.baselineFindingCategories.map jsonString)),
    ("current_finding_categories", jsonArray (delta.currentFindingCategories.map jsonString)),
    ("finding_categories_changed", renderBool delta.findingCategoriesChanged),
    ("baseline_boundary_shape", jsonArray (delta.baselineBoundaryShape.map renderBoundaryNodeJson)),
    ("current_boundary_shape", jsonArray (delta.currentBoundaryShape.map renderBoundaryNodeJson)),
    ("boundary_shape_changed", renderBool delta.boundaryShapeChanged)
  ]

/-- Render a complete delta report as stable minified JSON plus a trailing newline. -/
def renderJsonString (report : DeltaReport) : String :=
  jsonObject [
    ("schema_version", jsonString jsonSchemaVersion),
    ("tool_version", jsonString toolVersion),
    ("delta_model_version", jsonString reportModelVersion),
    ("baseline", renderArtifactMetadataJson report.baseline),
    ("current", renderArtifactMetadataJson report.current),
    ("summary", renderSummaryJson report.summary),
    ("changes", jsonArray (report.changes.map renderDeclarationDeltaJson)),
    ("limitations", jsonArray #[
      jsonString "compares rendered audit artifacts only",
      jsonString "does not re-run Lean elaboration",
      jsonString "does not validate proof axioms",
      jsonString "does not sandbox Lean execution",
      jsonString "does not prove theorem-statement equivalence",
      jsonString "does not suggest remediation"
    ])
  ] ++ "\n"

end LeanAssumptions.Delta
