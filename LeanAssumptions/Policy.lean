import LeanAssumptions.Core

/-!
Certified-path policy evaluation.

The policy layer consumes core assumption reports and produces deterministic
pass/warn/fail/audit-error results. It does not inspect Lean environments and
does not alter core classification results.
-/

namespace LeanAssumptions.Policy

open LeanAssumptions.Core

/-- Name-matching rules used by allowlists. Exact matching is the default. -/
inductive NamePattern where
  | exact (name : Lean.Name)
  | prefix (name : Lean.Name)
  deriving DecidableEq, Repr, Inhabited

/-- Configurable treatment for a policy-sensitive class of findings. -/
inductive AssumptionTreatment where
  | allow
  | warn
  | fail
  deriving DecidableEq, Repr, Inhabited

/-- Public policy result lattice. -/
inductive PolicyResult where
  | pass
  | warn
  | fail
  | auditError
  deriving DecidableEq, Repr, Inhabited

/-- Severity attached to an individual policy finding. -/
inductive PolicySeverity where
  | warning
  | failure
  | auditError
  deriving DecidableEq, Repr, Inhabited

/-- Machine-readable finding kinds emitted by deterministic policy evaluation. -/
inductive PolicyFindingKind where
  | unknownNode
  | cycleTruncated
  | unapprovedDirectProp
  | unapprovedPackageWithPropFields
  | unapprovedProofCarryingData
  | unapprovedTypeclassAssumption
  | unsupportedAlias
  | transparencyMismatch
  | policyTraversalBudgetExceeded
  deriving DecidableEq, Repr, Inhabited

/-- One deterministic policy finding for a node or report-level audit issue. -/
structure PolicyFinding where
  kind : PolicyFindingKind
  severity : PolicySeverity
  path : Array Lean.Name := #[]
  category : AssumptionCategory := .unknown
  typeName? : Option Lean.Name := none
  deriving Repr

/-- Policy configuration for the certified policy engine. -/
structure PolicyConfig where
  identifier : String := "strict"
  transparencyMode : TransparencyMode := .none
  permittedDirectProps : Array NamePattern := #[]
  permittedPackageTypes : Array NamePattern := #[]
  typeclassPolicy : AssumptionTreatment := .fail
  unknownPolicy : AssumptionTreatment := .fail
  aliasPolicy : AssumptionTreatment := .fail
  deriving Repr

/-- A completed deterministic policy evaluation. -/
structure PolicyEvaluation where
  result : PolicyResult
  findings : Array PolicyFinding
  deriving Repr

/-- Strict default policy: no direct, packaged, typeclass, alias, or unknown assumptions pass. -/
def strictPolicy : PolicyConfig := {}

/-- Render an assumption treatment canonically for policy digests. -/
private def canonicalTreatment : AssumptionTreatment → String
  | .allow => "allow"
  | .warn => "warn"
  | .fail => "fail"

/-- Render a transparency mode canonically for policy digests. -/
private def canonicalTransparency : TransparencyMode → String
  | .none => "none"
  | .reducible => "reducible"
  | .recursiveNormalization => "recursive_normalization"

/-- Render a name pattern canonically for policy digests. -/
def NamePattern.canonical : NamePattern → String
  | .exact name => s!"exact:{name}"
  | .prefix name => s!"prefix:{name}"

/-- Join strings with commas without depending on map iteration order. -/
private def joinComma : List String → String
  | [] => ""
  | [item] => item
  | item :: rest => item ++ "," ++ joinComma rest

/--
Canonical description of policy semantics.

The description covers every semantic field, sorts allowlists so that
equivalent policies agree, and excludes the human-facing identifier label.
It is versioned so future semantic fields force a visible digest change.
-/
def PolicyConfig.canonicalDescription (policy : PolicyConfig) : String :=
  let directs := (policy.permittedDirectProps.map NamePattern.canonical).qsort (· < ·)
  let packages := (policy.permittedPackageTypes.map NamePattern.canonical).qsort (· < ·)
  "policy-canonical-v1" ++
    ";transparency=" ++ canonicalTransparency policy.transparencyMode ++
    ";direct=[" ++ joinComma directs.toList ++ "]" ++
    ";package=[" ++ joinComma packages.toList ++ "]" ++
    ";typeclass=" ++ canonicalTreatment policy.typeclassPolicy ++
    ";unknown=" ++ canonicalTreatment policy.unknownPolicy ++
    ";alias=" ++ canonicalTreatment policy.aliasPolicy

/-- Render one hexadecimal digit for the low four bits of a value. -/
private def hexDigit (value : UInt64) : Char :=
  let nibble := (value &&& 0xf).toNat
  if nibble < 10 then
    Char.ofNat ('0'.toNat + nibble)
  else
    Char.ofNat ('a'.toNat + nibble - 10)

/-- Render a 64-bit value as 16 lowercase hexadecimal digits. -/
private def uint64ToHex (value : UInt64) : String :=
  String.ofList ((List.range 16).map fun index =>
    hexDigit (value >>> (UInt64.ofNat ((15 - index) * 4))))

/--
FNV-1a 64-bit hash of a string, rendered as fixed-width lowercase hex.

The hash is implemented locally so digests stay byte-stable across Lean
versions and platforms and remain auditable without dependencies.
-/
def fnv1a64Hex (input : String) : String :=
  let hash := input.toUTF8.foldl
    (fun acc byte => (acc ^^^ UInt64.ofNat byte.toNat) * 0x100000001b3)
    (0xcbf29ce484222325 : UInt64)
  uint64ToHex hash

/--
Deterministic digest identifying the policy semantics.

Two policies with the same semantic fields share a digest regardless of their
identifier labels, so artifact consumers can detect relabeled or modified
policies.
-/
def PolicyConfig.digest (policy : PolicyConfig) : String :=
  "fnv1a64:" ++ fnv1a64Hex policy.canonicalDescription

/-- Convert a Lean name into comparable path components for explicit prefix matching. -/
private def nameComponents : Lean.Name → List String
  | .anonymous => []
  | .str parent part => nameComponents parent ++ [part]
  | .num parent part => nameComponents parent ++ [toString part]

/-- Return `true` when the first list is a prefix of the second list. -/
private def listIsPrefix : List String → List String → Bool
  | [], _ => true
  | _ :: _, [] => false
  | expected :: restExpected, actual :: restActual =>
    expected == actual && listIsPrefix restExpected restActual

/-- Return whether a name pattern matches a concrete Lean name. -/
def NamePattern.matches (pattern : NamePattern) (name : Lean.Name) : Bool :=
  match pattern with
  | .exact expected => expected == name
  | .prefix expectedPrefix =>
    listIsPrefix (nameComponents expectedPrefix) (nameComponents name)

/-- Return whether any pattern in the array matches the name. -/
private def matchesAny (patterns : Array NamePattern) (name : Lean.Name) : Bool :=
  patterns.any (fun pattern => pattern.matches name)

/-- Return the syntactic head declaration of a type, if available in the report. -/
private def typeHeadName? (type : Lean.Expr) : Option Lean.Name :=
  match type.getAppFn with
  | .const name _ => some name
  | _ => none

/-- Return whether the syntactic type head is permitted by a type allowlist. -/
private def typeHeadPermitted (patterns : Array NamePattern) (type : Lean.Expr) : Bool :=
  match typeHeadName? type with
  | some name => matchesAny patterns name
  | none => false

/-- Convert a configurable treatment into an optional finding severity. -/
private def severityOfTreatment : AssumptionTreatment → Option PolicySeverity
  | .allow => none
  | .warn => some .warning
  | .fail => some .failure

/-- Return whether a node has a specific secondary flag. -/
private def hasFlag (node : BinderSurface) (flag : AssumptionFlag) : Bool :=
  node.secondaryFlags.any (fun actual => actual == flag)

/-- Construct one policy finding at a report path. -/
private def finding
    (kind : PolicyFindingKind)
    (severity : PolicySeverity)
    (path : Array Lean.Name)
    (node : BinderSurface) : PolicyFinding := {
  kind := kind
  severity := severity
  path := path
  category := node.primaryCategory
  typeName? := typeHeadName? node.binderType
}

/-- Append a finding governed by a configurable treatment. -/
private def pushTreatedFinding
    (findings : Array PolicyFinding)
    (treatment : AssumptionTreatment)
    (kind : PolicyFindingKind)
    (path : Array Lean.Name)
    (node : BinderSurface) : Array PolicyFinding :=
  match severityOfTreatment treatment with
  | none => findings
  | some severity => findings.push (finding kind severity path node)

/-- Work item for fuel-bounded, deterministic policy traversal. -/
private structure WorkItem where
  node : BinderSurface
  path : Array Lean.Name
  insidePackagedAssumption : Bool

/--
Evaluate policy findings owned by a single node.

Assumption-bearing package/typeclass/proof nodes own their internal direct
proposition fields for policy purposes; unknowns and cycle truncations still
surface even when they occur inside an approved package.
-/
private def evaluateOwnNode
    (policy : PolicyConfig)
    (insidePackagedAssumption : Bool)
    (path : Array Lean.Name)
    (node : BinderSurface)
    (findings : Array PolicyFinding) : Array PolicyFinding :=
  let findings :=
    if node.primaryCategory == .unknown then
      pushTreatedFinding findings policy.unknownPolicy .unknownNode path node
    else
      findings
  let findings :=
    if hasFlag node .cycleTruncated then
      findings.push (finding .cycleTruncated .failure path node)
    else
      findings
  if insidePackagedAssumption then
    findings
  else
    match node.primaryCategory with
    | .directProp =>
      if matchesAny policy.permittedDirectProps node.userName then
        findings
      else
        findings.push (finding .unapprovedDirectProp .failure path node)
    | .packageWithPropFields =>
      if typeHeadPermitted policy.permittedPackageTypes node.binderType then
        findings
      else
        findings.push (finding .unapprovedPackageWithPropFields .failure path node)
    | .proofCarryingData =>
      if typeHeadPermitted policy.permittedPackageTypes node.binderType then
        findings
      else
        findings.push (finding .unapprovedProofCarryingData .failure path node)
    | .typeclassAssumption =>
      pushTreatedFinding findings policy.typeclassPolicy .unapprovedTypeclassAssumption path node
    | .alias =>
      pushTreatedFinding findings policy.aliasPolicy .unsupportedAlias path node
    | .pureData | .unknown =>
      findings

/-- Return whether this node owns internal assumption-bearing children. -/
private def opensPackagedContext (node : BinderSurface) : Bool :=
  match node.primaryCategory with
  | .packageWithPropFields
  | .proofCarryingData
  | .typeclassAssumption
  | .alias => true
  | _ => false

/-- Conservative traversal budget for policy evaluation. -/
private def policyTraversalBudget : Nat := 10000

/-- Fuel-bounded deterministic preorder traversal of a report tree. -/
private def evaluateWork :
    PolicyConfig → Nat → List WorkItem → Array PolicyFinding → Array PolicyFinding
  | _, 0, [], findings => findings
  | _, 0, _ :: _, findings =>
    findings.push {
      kind := .policyTraversalBudgetExceeded
      severity := .auditError
      path := #[]
      category := .unknown
      typeName? := none
    }
  | _, _ + 1, [], findings => findings
  | policy, fuel + 1, item :: rest, findings =>
    let findings := evaluateOwnNode policy item.insidePackagedAssumption item.path item.node findings
    let childInsidePackagedAssumption :=
      item.insidePackagedAssumption || opensPackagedContext item.node
    let childItems :=
      item.node.children.toList.map fun child => {
        node := child
        path := item.path.push child.userName
        insidePackagedAssumption := childInsidePackagedAssumption
      }
    evaluateWork policy fuel (childItems ++ rest) findings

/-- Compute the final result from deterministic findings. -/
private def resultOfFindings (findings : Array PolicyFinding) : PolicyResult :=
  if findings.any (fun finding => finding.severity == .auditError) then
    .auditError
  else if findings.any (fun finding => finding.severity == .failure) then
    .fail
  else if findings.any (fun finding => finding.severity == .warning) then
    .warn
  else
    .pass

/-- Evaluate a core assumption report against a deterministic policy. -/
def evaluate (policy : PolicyConfig) (report : AssumptionReport) : PolicyEvaluation :=
  let findings : Array PolicyFinding :=
    if policy.transparencyMode == report.transparencyMode then
      #[]
    else
      #[{
        kind := .transparencyMismatch
        severity := .auditError
        path := #[]
        category := .unknown
        typeName? := none
      }]
  let initialWork :=
    report.binders.toList.map fun binder => {
      node := binder
      path := #[binder.userName]
      insidePackagedAssumption := false
      : WorkItem
    }
  -- A blocked result surface participates in policy evaluation like a binder:
  -- an alias-headed or unpeelable declaration surface must not pass silently.
  let resultWork :=
    match report.resultSurface? with
    | some node =>
      [{ node := node, path := #[node.userName], insidePackagedAssumption := false : WorkItem }]
    | none => []
  let findings := evaluateWork policy policyTraversalBudget (initialWork ++ resultWork) findings
  {
    result := resultOfFindings findings
    findings := findings
  }

end LeanAssumptions.Policy
