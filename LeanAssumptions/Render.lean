import LeanAssumptions.Policy
import LeanAssumptions.Version
import LeanAssumptions.JsonUtil

/-!
Deterministic rendering for assumption reports.

This support layer converts trusted core and policy outputs into stable text
and JSON artifacts. Renderer bugs must not affect `LeanAssumptions.Core` or
`LeanAssumptions.Policy` decisions.
-/

namespace LeanAssumptions.Render

open LeanAssumptions.Core
open LeanAssumptions.Policy

/-- A rendered report input: trusted core report plus deterministic policy evaluation. -/
structure ReportArtifact where
  report : AssumptionReport
  evaluation : PolicyEvaluation
  deriving Repr

/-- Machine-readable summary for batch CLI output. -/
structure BatchSummary where
  declarationsScanned : Nat
  declarationsPassed : Nat
  declarationsWarned : Nat
  declarationsFailed : Nat
  declarationsWithUnknownNodes : Nat
  deriving Repr

/-- Join strings with a separator without depending on map iteration order. -/
private def joinWith (separator : String) : List String -> String
  | [] => ""
  | [item] => item
  | item :: rest => item ++ separator ++ joinWith separator rest

/-- Convert a Lean name to the stable dotted form used in report artifacts. -/
private def renderName (name : Lean.Name) : String :=
  toString name

/--
Escape a fragment for single-line text output.

Names and string literals can contain newlines and control characters, which
would otherwise let a hostile declaration forge report lines such as a fake
`policy_result:` entry. Text output uses the same escaping as JSON strings so
one line in the artifact is always one logical field.
-/
private def sanitizeText (value : String) : String :=
  LeanAssumptions.JsonUtil.escapeString value

/-- Render a boolean using JSON-compatible spelling. -/
private def renderBool (value : Bool) : String :=
  if value then "true" else "false"

/-- Render a universe level deterministically. -/
private def renderLevel : Nat -> Lean.Level -> String
  | 0, _ => "level_truncated"
  | _, .zero => "0"
  | fuel + 1, .succ level => "succ(" ++ renderLevel fuel level ++ ")"
  | fuel + 1, .max left right =>
    "max(" ++ renderLevel fuel left ++ "," ++ renderLevel fuel right ++ ")"
  | fuel + 1, .imax left right =>
    "imax(" ++ renderLevel fuel left ++ "," ++ renderLevel fuel right ++ ")"
  | _, .param name => "param(" ++ renderName name ++ ")"
  | _, .mvar _ => "level_mvar"

/-- Render a Lean binder-info value deterministically. -/
private def renderLeanBinderInfo : Lean.BinderInfo -> String
  | .default => "explicit"
  | .implicit => "implicit"
  | .strictImplicit => "strict_implicit"
  | .instImplicit => "instance_implicit"

/-- Render a Lean literal deterministically, escaping embedded control text. -/
private def renderLiteral : Lean.Literal -> String
  | .natVal value => "nat(" ++ toString value ++ ")"
  | .strVal value => "str(" ++ LeanAssumptions.JsonUtil.escapeString value ++ ")"

/--
Render a Lean expression into a deterministic notation-resistant form.

Local free-variable identities generated during elaboration are intentionally
erased because their numeric suffixes are not reproducible report data.
-/
private def renderExprWithFuel : Nat -> Lean.Expr -> String
  | 0, _ => "expr_truncated"
  | _, .bvar index => "bvar(" ++ toString index ++ ")"
  | _, .fvar _ => "fvar"
  | _, .mvar _ => "mvar"
  | fuel + 1, .sort level => "sort(" ++ renderLevel fuel level ++ ")"
  | fuel + 1, .const name levels =>
    "const(" ++ renderName name ++ ",[" ++ joinWith "," (levels.map (renderLevel fuel)) ++ "])"
  | fuel + 1, .app fn arg =>
    "app(" ++ renderExprWithFuel fuel fn ++ "," ++ renderExprWithFuel fuel arg ++ ")"
  | fuel + 1, .lam name type body binderInfo =>
    "lam(" ++ renderName name ++ "," ++ renderLeanBinderInfo binderInfo ++ "," ++
      renderExprWithFuel fuel type ++ "," ++ renderExprWithFuel fuel body ++ ")"
  | fuel + 1, .forallE name type body binderInfo =>
    "forall(" ++ renderName name ++ "," ++ renderLeanBinderInfo binderInfo ++ "," ++
      renderExprWithFuel fuel type ++ "," ++ renderExprWithFuel fuel body ++ ")"
  | fuel + 1, .letE name type value body nondep =>
    "let(" ++ renderName name ++ "," ++ renderBool nondep ++ "," ++
      renderExprWithFuel fuel type ++ "," ++ renderExprWithFuel fuel value ++ "," ++
      renderExprWithFuel fuel body ++ ")"
  | _, .lit literal => "lit(" ++ renderLiteral literal ++ ")"
  | fuel + 1, .mdata _ body => "mdata(" ++ renderExprWithFuel fuel body ++ ")"
  | fuel + 1, .proj structName index body =>
    "proj(" ++ renderName structName ++ "," ++ toString index ++ "," ++
      renderExprWithFuel fuel body ++ ")"

/-- Convert a Lean expression to a deterministic notation-resistant representation. -/
private def renderExpr (expr : Lean.Expr) : String :=
  renderExprWithFuel 256 expr

/-- Rung-0 statement-identity digest: FNV-1a 64 over the deterministic
`raw_declaration_type_repr` encoding of the elaborated declaration type.
Byte-equal digests under the SAME `lean_version` certify that two artifacts
audited byte-identical elaborated statements (including binder display names —
stricter than alpha-equivalence). Equal digests across different
`lean_version` values certify nothing, and the digest never certifies
statement-meaning equivalence (see `docs/statement-identity-spec.md`). -/
def statementReprDigest (report : AssumptionReport) : String :=
  "fnv1a64:" ++ Policy.fnv1a64Hex (renderExpr report.declarationType)

/-- Render a transparency mode using public schema spelling. -/
private def renderTransparencyMode : TransparencyMode -> String
  | .none => "none"
  | .reducible => "reducible"
  | .recursiveNormalization => "recursive_normalization"

/-- Render a declaration kind using public schema spelling. -/
private def renderDeclarationKind : DeclarationKind -> String
  | .theorem => "theorem"
  | .definition => "definition"
  | .axiom => "axiom"
  | .opaque => "opaque"
  | .quotient => "quotient"
  | .inductive => "inductive"
  | .constructor => "constructor"
  | .recursor => "recursor"
  | .other => "other"

/-- Render a binder kind using public schema spelling. -/
private def renderBinderKind : SurfaceBinderKind -> String
  | .explicit => "explicit"
  | .implicit => "implicit"
  | .strictImplicit => "strict_implicit"
  | .instanceImplicit => "instance_implicit"

/-- Render an assumption category using public schema spelling. -/
private def renderAssumptionCategory : AssumptionCategory -> String
  | .pureData => "pure_data"
  | .directProp => "direct_prop"
  | .proofCarryingData => "proof_carrying_data"
  | .packageWithPropFields => "package_with_prop_fields"
  | .typeclassAssumption => "typeclass_assumption"
  | .alias => "alias"
  | .unknown => "unknown"

/-- Render a secondary assumption flag using public schema spelling. -/
private def renderAssumptionFlag : AssumptionFlag -> String
  | .binderTypeIsProp => "binder_type_is_prop"
  | .binderQuantifiesOverProp => "binder_quantifies_over_prop"
  | .instanceBinder => "instance_binder"
  | .cycleTruncated => "cycle_truncated"

/-- Render a policy result using public schema spelling. -/
private def renderPolicyResult : PolicyResult -> String
  | .pass => "pass"
  | .warn => "warn"
  | .fail => "fail"
  | .auditError => "audit_error"

/-- Render a policy severity using public schema spelling. -/
private def renderPolicySeverity : PolicySeverity -> String
  | .warning => "warning"
  | .failure => "failure"
  | .auditError => "audit_error"

/-- Render a policy finding kind using public schema spelling. -/
private def renderPolicyFindingKind : PolicyFindingKind -> String
  | .unknownNode => "unknown_node"
  | .cycleTruncated => "cycle_truncated"
  | .unapprovedDirectProp => "unapproved_direct_prop"
  | .unapprovedPackageWithPropFields => "unapproved_package_with_prop_fields"
  | .unapprovedProofCarryingData => "unapproved_proof_carrying_data"
  | .unapprovedTypeclassAssumption => "unapproved_typeclass_assumption"
  | .unsupportedAlias => "unsupported_alias"
  | .transparencyMismatch => "transparency_mismatch"
  | .policyTraversalBudgetExceeded => "policy_traversal_budget_exceeded"

/-- Repeat a string a fixed number of times. -/
private def repeatString : Nat -> String -> String
  | 0, _ => ""
  | n + 1, value => value ++ repeatString n value

/-- Map and concatenate a list deterministically. -/
private def concatMap (f : α -> List β) : List α -> List β
  | [] => []
  | item :: rest => f item ++ concatMap f rest

/-- Render a flag list for text output. -/
private def renderFlagSuffix (flags : Array AssumptionFlag) : String :=
  if flags.isEmpty then
    ""
  else
    " flags=[" ++ joinWith "," (flags.toList.map renderAssumptionFlag) ++ "]"

/-- Render one assumption-tree node and descendants for text output. -/
private def renderNodeText : Nat -> Nat -> BinderSurface -> List String
  | 0, indent, node =>
    let indentText := repeatString indent "  " ++ "- "
    [
      indentText ++ sanitizeText (renderName node.userName) ++ " : " ++
        renderAssumptionCategory node.primaryCategory ++
        " [" ++ renderBinderKind node.binderKind ++ "]" ++ renderFlagSuffix node.secondaryFlags ++
        " children_truncated_by_renderer"
    ]
  | fuel + 1, indent, node =>
    let indentText := repeatString indent "  " ++ "- "
    let line :=
      indentText ++ sanitizeText (renderName node.userName) ++ " : " ++
        renderAssumptionCategory node.primaryCategory ++
        " [" ++ renderBinderKind node.binderKind ++ "]" ++ renderFlagSuffix node.secondaryFlags
    line :: concatMap (renderNodeText fuel (indent + 1)) node.children.toList

/-- Conservative rendering traversal budget for report trees. -/
private def renderTraversalBudget : Nat := 10000

/-- Render one policy finding for text output. -/
private def renderFindingText (finding : PolicyFinding) : String :=
  let typeName :=
    match finding.typeName? with
    | some name => sanitizeText (renderName name)
    | none => "none"
  "- " ++ renderPolicyFindingKind finding.kind ++
    " severity=" ++ renderPolicySeverity finding.severity ++
    " path=" ++ sanitizeText (joinWith "." (finding.path.toList.map renderName)) ++
    " category=" ++ renderAssumptionCategory finding.category ++
    " type=" ++ typeName

/-- Render a complete report as stable human-readable text. -/
def renderText
    (policy : PolicyConfig)
    (report : AssumptionReport)
    (evaluation : PolicyEvaluation) : String :=
  let findingLines :=
    if evaluation.findings.isEmpty then
      ["- none"]
    else
      evaluation.findings.toList.map renderFindingText
  let lines :=
    [
      "lean-assumptions report",
      "tool_version: " ++ toolVersion,
      "lean_version: " ++ Lean.versionString,
      "schema_version: " ++ jsonSchemaVersion,
      "report_model_version: " ++ reportModelVersion,
      "target: " ++ sanitizeText (renderName report.declarationName),
      "declaration_kind: " ++ renderDeclarationKind report.declarationKind,
      "transparency_mode: " ++ renderTransparencyMode report.transparencyMode,
      "policy_identifier: " ++ sanitizeText policy.identifier,
      "policy_digest: " ++ policy.digest,
      "policy_result: " ++ renderPolicyResult evaluation.result,
      "unknowns_occurred: " ++ renderBool report.unknownsOccurred,
      "cycles_truncated: " ++ renderBool report.cyclesTruncated,
      "transparency_limited: " ++ renderBool report.transparencyLimited,
      "assumption_tree:"
    ] ++ concatMap (renderNodeText renderTraversalBudget 0) report.binders.toList ++
    (match report.resultSurface? with
      | some node => "result_surface:" :: renderNodeText renderTraversalBudget 0 node
      | none => []) ++
    ["policy_findings:"] ++ findingLines ++
    [
      "raw_declaration_type_repr: " ++ renderExpr report.declarationType,
      "statement_repr_digest: " ++ statementReprDigest report,
      "result_type_repr: " ++ renderExpr report.resultType,
      "limitations: audits elaborated declaration types only; does not validate proof axioms, sandbox execution, or theorem-statement equivalence."
    ]
  joinWith "\n" lines ++ "\n"

/-- Quote a JSON string. -/
private def jsonString (value : String) : String :=
  LeanAssumptions.JsonUtil.quoteString value

/-- Render an optional name as JSON. -/
private def jsonOptionalName : Option Lean.Name -> String
  | some name => jsonString (renderName name)
  | none => "null"

/-- Render a JSON array from already-rendered JSON items. -/
private def jsonArray (items : Array String) : String :=
  "[" ++ joinWith "," items.toList ++ "]"

/-- Render a JSON object from already-rendered key/value fields. -/
private def jsonObject (fields : List (Prod String String)) : String :=
  "{" ++ joinWith "," (fields.map fun field => jsonString field.fst ++ ":" ++ field.snd) ++ "}"

/-- Render one assumption-tree node as deterministic JSON. -/
private def renderNodeJson : Nat -> BinderSurface -> String
  | 0, node =>
    jsonObject [
      ("name", jsonString (renderName node.userName)),
      ("binder_kind", jsonString (renderBinderKind node.binderKind)),
      ("primary_category", jsonString (renderAssumptionCategory node.primaryCategory)),
      ("secondary_flags", jsonArray (node.secondaryFlags.map fun flag => jsonString (renderAssumptionFlag flag))),
      ("binder_type_repr", jsonString (renderExpr node.binderType)),
      ("children", jsonArray #[]),
      ("renderer_children_truncated", "true")
    ]
  | fuel + 1, node =>
    jsonObject [
      ("name", jsonString (renderName node.userName)),
      ("binder_kind", jsonString (renderBinderKind node.binderKind)),
      ("primary_category", jsonString (renderAssumptionCategory node.primaryCategory)),
      ("secondary_flags", jsonArray (node.secondaryFlags.map fun flag => jsonString (renderAssumptionFlag flag))),
      ("binder_type_repr", jsonString (renderExpr node.binderType)),
      ("children", jsonArray (node.children.map (renderNodeJson fuel))),
      ("renderer_children_truncated", "false")
    ]

/-- Render one policy finding as deterministic JSON. -/
private def renderFindingJson (finding : PolicyFinding) : String :=
  jsonObject [
    ("kind", jsonString (renderPolicyFindingKind finding.kind)),
    ("severity", jsonString (renderPolicySeverity finding.severity)),
    ("path", jsonArray (finding.path.map fun name => jsonString (renderName name))),
    ("category", jsonString (renderAssumptionCategory finding.category)),
    ("type_name", jsonOptionalName finding.typeName?)
  ]

/-- Render a complete report as stable minified JSON plus a trailing newline. -/
private def renderJsonCore
    (policy : PolicyConfig)
    (report : AssumptionReport)
    (evaluation : PolicyEvaluation) : String :=
  jsonObject [
    ("schema_version", jsonString jsonSchemaVersion),
    ("tool_version", jsonString toolVersion),
    ("lean_version", jsonString Lean.versionString),
    ("report_model_version", jsonString reportModelVersion),
    ("target", jsonString (renderName report.declarationName)),
    ("declaration_kind", jsonString (renderDeclarationKind report.declarationKind)),
    ("transparency_mode", jsonString (renderTransparencyMode report.transparencyMode)),
    ("policy_identifier", jsonString policy.identifier),
    ("policy_digest", jsonString policy.digest),
    ("policy_result", jsonString (renderPolicyResult evaluation.result)),
    ("unknowns_occurred", renderBool report.unknownsOccurred),
    ("cycles_truncated", renderBool report.cyclesTruncated),
    ("transparency_limited", renderBool report.transparencyLimited),
    ("raw_declaration_type_repr", jsonString (renderExpr report.declarationType)),
    ("statement_repr_digest", jsonString (statementReprDigest report)),
    ("result_type_repr", jsonString (renderExpr report.resultType)),
    ("assumption_tree", jsonArray (report.binders.map (renderNodeJson renderTraversalBudget))),
    ("result_surface",
      match report.resultSurface? with
      | some node => renderNodeJson renderTraversalBudget node
      | none => "null"),
    ("policy_findings", jsonArray (evaluation.findings.map renderFindingJson)),
    ("limitations", jsonArray #[
      jsonString "audits elaborated declaration types only",
      jsonString "does not validate proof axioms",
      jsonString "does not sandbox Lean execution",
      jsonString "does not prove theorem-statement equivalence"
    ])
  ]

/-- Render a complete report as stable minified JSON plus a trailing newline. -/
def renderJsonString
    (policy : PolicyConfig)
    (report : AssumptionReport)
    (evaluation : PolicyEvaluation) : String :=
  renderJsonCore policy report evaluation ++ "\n"

/-- Return whether the policy result is a failing result for CI exit-code purposes. -/
def policyResultIsFailure : PolicyResult -> Bool
  | .fail | .auditError => true
  | .pass | .warn => false

/-- Return whether the policy result is a warning result. -/
private def policyResultIsWarning : PolicyResult -> Bool
  | .warn => true
  | .pass | .fail | .auditError => false

/-- Compute a deterministic batch summary from report artifacts. -/
def summarizeBatch (artifacts : Array ReportArtifact) : BatchSummary := {
  declarationsScanned := artifacts.size
  declarationsPassed := artifacts.foldl (fun count artifact =>
    if artifact.evaluation.result == .pass then count + 1 else count) 0
  declarationsWarned := artifacts.foldl (fun count artifact =>
    if policyResultIsWarning artifact.evaluation.result then count + 1 else count) 0
  declarationsFailed := artifacts.foldl (fun count artifact =>
    if policyResultIsFailure artifact.evaluation.result then count + 1 else count) 0
  declarationsWithUnknownNodes := artifacts.foldl (fun count artifact =>
    if artifact.report.unknownsOccurred then count + 1 else count) 0
}

/-- Render a batch summary as stable text lines. -/
private def renderBatchSummaryText (summary : BatchSummary) : List String := [
  "batch_summary:",
  "declarations_scanned: " ++ toString summary.declarationsScanned,
  "declarations_passed: " ++ toString summary.declarationsPassed,
  "declarations_warned: " ++ toString summary.declarationsWarned,
  "declarations_failed: " ++ toString summary.declarationsFailed,
  "declarations_with_unknown_nodes: " ++ toString summary.declarationsWithUnknownNodes,
  "schema_version: " ++ jsonSchemaVersion
]

/--
Render the batch summary block exactly as `renderBatchText` appends it.

Streaming emitters print per-report text incrementally and then this block,
producing bytes identical to `renderBatchText`.
-/
def renderBatchSummaryTextBlock (artifacts : Array ReportArtifact) : String :=
  joinWith "\n" (renderBatchSummaryText (summarizeBatch artifacts)) ++ "\n"

/-- Render a batch of reports as deterministic human-readable text. -/
def renderBatchText (policy : PolicyConfig) (artifacts : Array ReportArtifact) : String :=
  let reports := artifacts.toList.map fun artifact =>
    renderText policy artifact.report artifact.evaluation
  joinWith "\n" reports ++ renderBatchSummaryTextBlock artifacts

/-- Render a batch summary as deterministic JSON. -/
private def renderBatchSummaryJson (summary : BatchSummary) : String :=
  jsonObject [
    ("declarations_scanned", toString summary.declarationsScanned),
    ("declarations_passed", toString summary.declarationsPassed),
    ("declarations_warned", toString summary.declarationsWarned),
    ("declarations_failed", toString summary.declarationsFailed),
    ("declarations_with_unknown_nodes", toString summary.declarationsWithUnknownNodes),
    ("schema_version", jsonString jsonSchemaVersion)
  ]

/-- Render a batch of reports as stable minified JSON plus a trailing newline. -/
def renderBatchJsonString (policy : PolicyConfig) (artifacts : Array ReportArtifact) : String :=
  let summary := summarizeBatch artifacts
  jsonObject [
    ("schema_version", jsonString jsonSchemaVersion),
    ("tool_version", jsonString toolVersion),
    ("lean_version", jsonString Lean.versionString),
    ("policy_identifier", jsonString policy.identifier),
    ("policy_digest", jsonString policy.digest),
    ("transparency_mode", jsonString (renderTransparencyMode policy.transparencyMode)),
    ("summary", renderBatchSummaryJson summary),
    ("reports", jsonArray (artifacts.map fun artifact =>
      renderJsonCore policy artifact.report artifact.evaluation))
  ] ++ "\n"

end LeanAssumptions.Render
