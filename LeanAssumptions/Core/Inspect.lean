import LeanAssumptions.Core.Model

/-!
Certified-path declaration inspection and assumption-surface classification.

This module inspects elaborated declaration types, peels outer binders, expands
supported structure/class packages recursively, detects the Phase 2
proof-carrying wrappers, and reports unknown/cycle truncation conservatively.
-/
open Lean Meta Elab Command

namespace LeanAssumptions.Core

/--
Maximum recursive package-expansion depth.

The bound keeps the certified path structurally recursive rather than relying
on unbounded recursion. Exhausting the bound yields an `unknown` node.
-/
private def maxExpansionDepth : Nat := 64

/-- Internal result for recursive node inspection. -/
private structure InspectSummary where
  node : BinderSurface
  unknownsOccurred : Bool
  cyclesTruncated : Bool

/-- Internal result for a deterministic sequence of inspected children. -/
private structure ChildSummary where
  children : Array BinderSurface := #[]
  unknownsOccurred : Bool := false
  cyclesTruncated : Bool := false

/-- Evidence that a binder contributes directly to the proposition surface. -/
private structure DirectPropSurfaceEvidence where
  binderTypeIsProp : Bool := false
  binderQuantifiesOverProp : Bool := false

/-- Return `true` when either direct-proposition diagnostic path was observed. -/
private def DirectPropSurfaceEvidence.contributes (evidence : DirectPropSurfaceEvidence) : Bool :=
  evidence.binderTypeIsProp || evidence.binderQuantifiesOverProp

/-- Return the syntactic declaration head of a type without transparency expansion. -/
private def rawTypeHeadName? (type : Lean.Expr) : Option Lean.Name :=
  match type.getAppFn with
  | .const name _ => some name
  | _ => none

/-- Return `true` when a declaration is a generated structure projection. -/
private def isProjectionFunction (declName : Lean.Name) : MetaM Bool := do
  let env ← getEnv
  match declName with
  | .str parent field =>
    let some structInfo := Lean.getStructureInfo? env parent | return false
    pure (Lean.getProjFnForField? env parent (.mkSimple field) == declName ||
      structInfo.parentInfo.any (fun parentInfo => parentInfo.projFn == declName))
  | _ => pure false

/-- Return `true` when a declaration head is a reducible abbreviation. -/
private def isReducibleAliasHead (name : Lean.Name) : MetaM Bool := do
  if ← isProjectionFunction name then
    return false
  let env ← getEnv
  match env.find? name with
  | some (.defnInfo info) =>
    match info.hints with
    | .abbrev => pure true
    | _ => pure false
  | _ => pure false

/-- Return `true` when a type's syntactic head is a reducible alias. -/
private def isReducibleAliasType (type : Lean.Expr) : MetaM Bool := do
  match rawTypeHeadName? type with
  | some name => isReducibleAliasHead name
  | none => pure false

/-- Fuel for project-defined recursive normalization. -/
private def normalizationFuel : Nat := 64

/-- Repeatedly normalize reducible heads until a fixed point or fuel exhaustion. -/
private def recursivelyNormalizeType : Nat → Lean.Expr → MetaM Lean.Expr
  | 0, type => pure type
  | fuel + 1, type => do
    let reduced ← whnf type
    if reduced == type then
      pure reduced
    else
      recursivelyNormalizeType fuel reduced

/-- Normalize a type according to the requested report transparency mode. -/
private def normalizeTypeForMode (mode : TransparencyMode) (type : Lean.Expr) : MetaM Lean.Expr := do
  match mode with
  | .none => pure type
  | .reducible => whnf type
  | .recursiveNormalization => recursivelyNormalizeType normalizationFuel type

/-- Convert Lean's binder-info representation into the public surface kind. -/
private def surfaceBinderKindOf (binderInfo : Lean.BinderInfo) : SurfaceBinderKind :=
  match binderInfo with
  | .default => .explicit
  | .implicit => .implicit
  | .strictImplicit => .strictImplicit
  | .instImplicit => .instanceImplicit

/-- Normalize Lean declaration kinds into the report-model view. -/
private def declarationKindOf (info : Lean.ConstantInfo) : DeclarationKind :=
  match info with
  | .thmInfo _ => .theorem
  | .defnInfo _ => .definition
  | .axiomInfo _ => .axiom
  | .opaqueInfo _ => .opaque
  | .quotInfo _ => .quotient
  | .inductInfo _ => .inductive
  | .ctorInfo _ => .constructor
  | .recInfo _ => .recursor

/-- Return the declaration name at the normalized head of a type, if one is present. -/
private def typeHeadName? (type : Lean.Expr) : MetaM (Option Lean.Name) := do
  pure (rawTypeHeadName? (← whnf type))

/-- Return `true` when `type` is headed by a registered structure/class. -/
private def isStructureApplication (type : Lean.Expr) : MetaM Bool := do
  let some headName := rawTypeHeadName? type | return false
  let env ← getEnv
  pure (Lean.getStructureInfo? env headName).isSome

/--
Classify the two direct-proposition surface diagnostics separately.

A binder such as `(h : P)` has a proposition as its type and binds proof data.
A binder such as `(P : Prop)` ranges over propositions. Strict policy rejects
both as `direct_prop`, but reports keep the two evidence paths distinct.
-/
private def directPropSurfaceEvidence (binderType : Lean.Expr) :
    MetaM DirectPropSurfaceEvidence := do
  let binderTypeIsProp ← Meta.isProp binderType
  let binderQuantifiesOverProp ←
    match (← whnf binderType) with
    | .sort level => pure (level == .zero)
    | _ => pure false
  pure {
    binderTypeIsProp := binderTypeIsProp
    binderQuantifiesOverProp := binderQuantifiesOverProp
  }

/-- Return `true` when the binder contributes directly to the proposition surface. -/
private def bindsDirectPropSurface (binderType : Lean.Expr) : MetaM Bool := do
  let evidence ← directPropSurfaceEvidence binderType
  pure evidence.contributes

/-- Return `true` when an application argument is itself proposition-like. -/
private def hasProofLikeArgument (type : Lean.Expr) : MetaM Bool := do
  for arg in (← whnf type).getAppArgs do
    if ← bindsDirectPropSurface arg then
      return true
  return false

/--
Return `true` for Lean wrapper applications that carry proof data through one
of their arguments, without claiming that the wrapper itself is a proposition.
-/
private def proofLikeWrapperApplication (type : Lean.Expr) : MetaM Bool := do
  match ← typeHeadName? type with
  | some ``PLift => hasProofLikeArgument type
  | _ => pure false

/--
Return `true` when the type is one of the mandatory proof-carrying data patterns
whose proof component is visible under the current conservative rules.
-/
private def isProofCarryingDataType (type : Lean.Expr) : MetaM Bool := do
  let type ← whnf type
  match type.getAppFn with
  | .const ``Subtype _ =>
    pure true
  | .const ``Sigma _ =>
    inspectDependentPayloadForProof type
  | .const ``PSigma _ =>
    inspectDependentPayloadForProof type
  | _ =>
    proofLikeWrapperApplication type
where
  inspectDependentPayloadForProof (type : Lean.Expr) : MetaM Bool := do
    let args := type.getAppArgs
    if h : 1 < args.size then
      let payloadFamily := args[1]
      forallTelescopeReducing (← inferType payloadFamily) fun fvars _ => do
        let payloadType := mkAppN payloadFamily fvars
        if ← bindsDirectPropSurface payloadType then
          return true
        else
          proofLikeWrapperApplication payloadType
    else
      pure false

/--
Classify a binder or package field before parent package evidence is considered.

Instance-implicit binders remain `typeclass_assumption` as their primary
category while still exposing inspected children. Non-instance proposition
binders are `direct_prop`; mandatory proof-carrying wrappers are
`proof_carrying_data`; all other nodes start as `pure_data`.
-/
private def classifySurface
    (binderKind : SurfaceBinderKind)
    (binderType : Lean.Expr) : MetaM (AssumptionCategory × Array AssumptionFlag) := do
  let directPropEvidence ← directPropSurfaceEvidence binderType
  let bindsDirectPropSurface := directPropEvidence.contributes
  let proofCarryingData : Bool := ← isProofCarryingDataType binderType
  let primaryCategory :=
    if binderKind == .instanceImplicit then
      AssumptionCategory.typeclassAssumption
    else if bindsDirectPropSurface then
      AssumptionCategory.directProp
    else if proofCarryingData then
      AssumptionCategory.proofCarryingData
    else
      AssumptionCategory.pureData
  let mut secondaryFlags : Array AssumptionFlag := #[]
  if directPropEvidence.binderTypeIsProp then
    secondaryFlags := secondaryFlags.push .binderTypeIsProp
  if directPropEvidence.binderQuantifiesOverProp then
    secondaryFlags := secondaryFlags.push .binderQuantifiesOverProp
  if binderKind == .instanceImplicit then
    secondaryFlags := secondaryFlags.push .instanceBinder
  pure (primaryCategory, secondaryFlags)

/-- Return `true` when a child contributes an assumption surface to its parent. -/
private def childContributesAssumption (child : BinderSurface) : Bool :=
  match child.primaryCategory with
  | .directProp
  | .proofCarryingData
  | .packageWithPropFields
  | .typeclassAssumption => true
  | _ => false

/-- Adjust a node's primary category after recursive children are known. -/
private def classifyWithChildren
    (binderKind : SurfaceBinderKind)
    (binderType : Lean.Expr)
    (children : Array BinderSurface) : MetaM (AssumptionCategory × Array AssumptionFlag) := do
  let (primaryCategory, secondaryFlags) ← classifySurface binderKind binderType
  if primaryCategory == .pureData then
    if children.any childContributesAssumption then
      pure (.packageWithPropFields, secondaryFlags)
    else if children.any (fun child => child.primaryCategory == .unknown) then
      pure (.unknown, secondaryFlags)
    else
      pure (primaryCategory, secondaryFlags)
  else
    pure (primaryCategory, secondaryFlags)

/-- Return an explicitly unknown node for an expansion path that cannot continue. -/
private def unknownNode
    (userName : Lean.Name)
    (binderType : Lean.Expr)
    (binderKind : SurfaceBinderKind)
    (flags : Array AssumptionFlag := #[]) : BinderSurface := {
  userName := userName
  binderType := binderType
  binderKind := binderKind
  primaryCategory := .unknown
  secondaryFlags := flags
}

/-- Return an explicitly reported alias node for expansion blocked by transparency. -/
private def aliasNode
    (userName : Lean.Name)
    (binderType : Lean.Expr)
    (binderKind : SurfaceBinderKind) : BinderSurface :=
  let secondaryFlags :=
    if binderKind == .instanceImplicit then
      #[AssumptionFlag.instanceBinder]
    else
      #[]
  {
    userName := userName
    binderType := binderType
    binderKind := binderKind
    primaryCategory := .alias
    secondaryFlags := secondaryFlags
  }

/-- Inspect one surface binder or package field with bounded recursive expansion. -/
private def inspectNode :
    TransparencyMode → Nat → Array Lean.Name → Lean.Name → Lean.Expr → SurfaceBinderKind →
      MetaM InspectSummary
  | _, 0, _, userName, value, binderKind => do
    let binderType ← inferType value
    pure {
      node := unknownNode userName binderType binderKind
      unknownsOccurred := true
      cyclesTruncated := false
    }
  | transparencyMode, fuel + 1, visited, userName, value, binderKind => do
    let rawBinderType ← inferType value
    if transparencyMode == .none && (← isReducibleAliasType rawBinderType) then
      return {
        node := aliasNode userName rawBinderType binderKind
        unknownsOccurred := false
        cyclesTruncated := false
      }
    let binderType ← normalizeTypeForMode transparencyMode rawBinderType
    let mut children : Array BinderSurface := #[]
    let mut unknownsOccurred := false
    let mut cyclesTruncated := false
    let type := binderType
    match type.getAppFn with
    | .const structName _ =>
      if ← isStructureApplication type then
        if visited.contains structName then
          return {
            node := unknownNode userName binderType binderKind #[.cycleTruncated]
            unknownsOccurred := true
            cyclesTruncated := true
          }
        else
          let env ← getEnv
          match Lean.getStructureInfo? env structName with
          | none =>
            children := #[]
          | some structInfo =>
            let nextVisited := visited.push structName
            let mut childSummary : ChildSummary := {}
            for fieldName in structInfo.fieldNames do
              let fieldResult ←
                match Lean.getFieldInfo? env structName fieldName with
                | none =>
                  pure {
                    node := unknownNode fieldName type .explicit
                    unknownsOccurred := true
                    cyclesTruncated := false
                  }
                | some fieldInfo =>
                  try
                    let projection ← Meta.mkProjection value fieldName
                    inspectNode transparencyMode fuel nextVisited fieldName projection
                      (surfaceBinderKindOf fieldInfo.binderInfo)
                  catch _ =>
                    pure {
                      node := unknownNode fieldName type (surfaceBinderKindOf fieldInfo.binderInfo)
                      unknownsOccurred := true
                      cyclesTruncated := false
                    }
              childSummary := {
                children := childSummary.children.push fieldResult.node
                unknownsOccurred := childSummary.unknownsOccurred || fieldResult.unknownsOccurred
                cyclesTruncated := childSummary.cyclesTruncated || fieldResult.cyclesTruncated
              }
            children := childSummary.children
            unknownsOccurred := childSummary.unknownsOccurred
            cyclesTruncated := childSummary.cyclesTruncated
    | _ => pure ()
    let (primaryCategory, secondaryFlags) ← classifyWithChildren binderKind binderType children
    pure {
      node := {
        userName := userName
        binderType := binderType
        binderKind := binderKind
        primaryCategory := primaryCategory
        secondaryFlags := secondaryFlags
        children := children
      }
      unknownsOccurred := unknownsOccurred || primaryCategory == .unknown
      cyclesTruncated := cyclesTruncated
    }

/-- Inspect a declaration from the current environment inside `MetaM`. -/
private def inspectDeclarationMeta
    (transparencyMode : TransparencyMode)
    (declName : Lean.Name) : MetaM AssumptionReport := do
  let constantInfo ← getConstInfo declName
  let declarationType := constantInfo.type
  forallTelescope declarationType fun binderFVars resultType => do
    let mut binders : Array BinderSurface := #[]
    let mut unknownsOccurred := false
    let mut cyclesTruncated := false
    for binderFVar in binderFVars do
      let localDecl ← binderFVar.fvarId!.getDecl
      let binderKind := surfaceBinderKindOf localDecl.binderInfo
      let summary ← inspectNode transparencyMode maxExpansionDepth #[] localDecl.userName binderFVar binderKind
      binders := binders.push summary.node
      unknownsOccurred := unknownsOccurred || summary.unknownsOccurred
      cyclesTruncated := cyclesTruncated || summary.cyclesTruncated
    pure {
      declarationName := declName
      declarationKind := declarationKindOf constantInfo
      declarationType := declarationType
      binders := binders
      resultType := resultType
      transparencyMode := transparencyMode
      unknownsOccurred := unknownsOccurred
      cyclesTruncated := cyclesTruncated
    }

/--
Inspect a declaration visible in the current command-elaboration environment.

This is the thin certified-path adapter used by tests and later support layers.
Policy evaluation stays in `LeanAssumptions.Policy`; command, CLI, and rendering
adapters must not silently alter this report.
-/
def inspectDeclaration (declName : Lean.Name) : CommandElabM AssumptionReport :=
  liftTermElabM <| inspectDeclarationMeta .none declName

/--
Inspect a declaration under an explicit alias-transparency mode.

With `.none`, reducible aliases are reported as `alias` nodes rather than
silently expanded. With `.reducible`, abbreviation heads are reduced enough to
classify the exposed package. With `.recursiveNormalization`, the project
normalizer repeatedly applies the same reducible-head normalization at each
inspection node.
-/
def inspectDeclarationWithTransparency
    (transparencyMode : TransparencyMode)
    (declName : Lean.Name) : CommandElabM AssumptionReport :=
  liftTermElabM <| inspectDeclarationMeta transparencyMode declName

end LeanAssumptions.Core
