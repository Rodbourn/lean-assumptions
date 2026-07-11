import LeanAssumptions.Core.Model

/-!
Certified-path declaration inspection and assumption-surface classification.

This module inspects elaborated declaration types, peels outer binders, and
classifies each binder type by positive recognition of its normalized head
shape. Structures and classes expand recursively into fields. Non-structure
inductive types are scanned constructor by constructor for proposition-bearing
content. Function types are classified through their result type, and `Quot`
types through their payload type. Any head shape that is not positively
recognized is reported as `unknown`, so classification ambiguity can never
resolve optimistically.

Structural reduction (beta, zeta, projection) is always applied before head
recognition. Delta expansion of constants is governed by the report
transparency mode.
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

/--
Normalize a type according to the requested report transparency mode.

Every mode applies structural reduction (beta, zeta, projection) so that head
recognition cannot be defeated by wrapping a type in a redex. Only the
`reducible` and `recursive_normalization` modes additionally unfold constant
heads.
-/
private def normalizeTypeForMode (mode : TransparencyMode) (type : Lean.Expr) : MetaM Lean.Expr := do
  match mode with
  | .none => whnfCore type
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

The quantifier diagnostic matches the already-normalized type syntactically so
that constant heads are never unfolded beyond the report transparency mode.
-/
private def directPropSurfaceEvidence (binderType : Lean.Expr) :
    MetaM DirectPropSurfaceEvidence := do
  let binderTypeIsProp ← Meta.isProp binderType
  let binderQuantifiesOverProp :=
    match binderType with
    | .sort level => level == .zero
    | _ => false
  pure {
    binderTypeIsProp := binderTypeIsProp
    binderQuantifiesOverProp := binderQuantifiesOverProp
  }

/-- Return `true` when the binder contributes directly to the proposition surface. -/
private def bindsDirectPropSurface (binderType : Lean.Expr) : MetaM Bool := do
  let evidence ← directPropSurfaceEvidence (← whnfCore binderType)
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
        -- `Sigma` payloads live in `Type`, so this direct-`Prop` check is
        -- only reachable for `PSigma`; the wrapper check below is meaningful
        -- for both families.
        if ← bindsDirectPropSurface payloadType then
          return true
        else
          proofLikeWrapperApplication payloadType
    else
      pure false

/-- Return `true` when a child contributes an assumption surface to its parent. -/
private def childContributesAssumption (child : BinderSurface) : Bool :=
  match child.primaryCategory with
  | .directProp
  | .proofCarryingData
  | .packageWithPropFields
  | .typeclassAssumption => true
  | _ => false

/-- Return `true` when a child blocks positive classification of its parent. -/
private def childBlocksClassification (child : BinderSurface) : Bool :=
  match child.primaryCategory with
  | .unknown
  | .alias => true
  | _ => false

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

/-- Return the final component of a name for deterministic child labels. -/
private def shortNameOf (name : Lean.Name) : String :=
  match name with
  | .str _ suffix => suffix
  | other => toString other

/-- Return a deterministic constructor-field label, replacing inaccessible names. -/
private def constructorFieldLabel
    (ctorName : Lean.Name) (fieldUserName : Lean.Name) (fieldIndex : Nat) : Lean.Name :=
  let fieldPart :=
    if fieldUserName.hasMacroScopes || fieldUserName.isAnonymous then
      s!"field{fieldIndex}"
    else
      toString fieldUserName
  Lean.Name.mkStr (Lean.Name.mkSimple (shortNameOf ctorName)) fieldPart

/--
Inspect one surface binder or package field with bounded recursive expansion.

Classification is by positive recognition of the normalized head shape:

- proposition evidence yields `direct_prop`
- mandatory proof-carrying wrappers yield `proof_carrying_data`
- registered structures and classes expand recursively into fields
- sorts and locally bound type variables are pure data
- non-structure inductive heads are scanned constructor by constructor, and
  proposition-bearing constructor fields yield `proof_carrying_data`
- function types are classified through their result type
- `Quot` applications are classified through their payload type
- every other head shape is reported as `unknown`

Constructor fields whose type is exactly the scanned application are recursive
occurrences and are skipped; their content is covered by the surrounding scan.
Children of inductive, function, and `Quot` nodes are retained only when they
contribute assumptions or block classification. A child that remains an
unexpanded `alias` or `unknown` blocks positive classification of its parent,
so such parents report `unknown` rather than `pure_data`.
-/
private def inspectNode :
    TransparencyMode → Nat → Array Lean.Name → Lean.Name → Lean.Expr → SurfaceBinderKind →
      MetaM InspectSummary
  | _, 0, _, userName, binderTypeRaw, binderKind => do
    pure {
      node := unknownNode userName binderTypeRaw binderKind
      unknownsOccurred := true
      cyclesTruncated := false
    }
  | transparencyMode, fuel + 1, visited, userName, binderTypeRaw, binderKind => do
    if transparencyMode == .none && (← isReducibleAliasType binderTypeRaw) then
      return {
        node := aliasNode userName binderTypeRaw binderKind
        unknownsOccurred := false
        cyclesTruncated := false
      }
    let binderType ← normalizeTypeForMode transparencyMode binderTypeRaw
    let evidence ← directPropSurfaceEvidence binderType
    let proofCarryingWrapper ← isProofCarryingDataType binderType
    let isStructApp ← isStructureApplication binderType
    let mut children : Array BinderSurface := #[]
    let mut unknownsOccurred := false
    let mut cyclesTruncated := false
    let mut headRecognized := false
    if isStructApp then
      -- Structure and class applications expand into fields for every binder
      -- kind and category, so packaged content stays visible in the report.
      headRecognized := true
      match binderType.getAppFn with
      | .const structName _ =>
        if visited.contains structName then
          return {
            node := unknownNode userName binderType binderKind #[.cycleTruncated]
            unknownsOccurred := true
            cyclesTruncated := true
          }
        let env ← getEnv
        match Lean.getStructureInfo? env structName with
        | none => pure ()
        | some structInfo =>
          let nextVisited := visited.push structName
          let structSummary ← withLocalDeclD `packageValue binderType fun packageValue => do
            let mut summary : ChildSummary := {}
            for fieldName in structInfo.fieldNames do
              let mut fieldResult : InspectSummary := {
                node := unknownNode fieldName binderType .explicit
                unknownsOccurred := true
                cyclesTruncated := false
              }
              match Lean.getFieldInfo? env structName fieldName with
              | none => pure ()
              | some fieldInfo =>
                try
                  let projection ← Meta.mkProjection packageValue fieldName
                  let fieldType ← inferType projection
                  fieldResult ← inspectNode transparencyMode fuel nextVisited fieldName
                    fieldType (surfaceBinderKindOf fieldInfo.binderInfo)
                catch _ =>
                  fieldResult := {
                    node := unknownNode fieldName binderType
                      (surfaceBinderKindOf fieldInfo.binderInfo)
                    unknownsOccurred := true
                    cyclesTruncated := false
                  }
              summary := {
                children := summary.children.push fieldResult.node
                unknownsOccurred := summary.unknownsOccurred || fieldResult.unknownsOccurred
                cyclesTruncated := summary.cyclesTruncated || fieldResult.cyclesTruncated
              }
            pure summary
          children := structSummary.children
          unknownsOccurred := structSummary.unknownsOccurred
          cyclesTruncated := structSummary.cyclesTruncated
      | _ => pure ()
    else if binderKind == .instanceImplicit ||
        (!evidence.contributes && !proofCarryingWrapper) then
      -- Non-structure head recognition runs for data candidates and for
      -- instance binders, whose packaged content must stay visible.
      match binderType.getAppFn with
      | .sort _ =>
        headRecognized := true
      | .fvar _ =>
        -- A locally bound type or type-family variable: the surrounding
        -- telescope quantifies over it, so its values are parametric data.
        headRecognized := true
      | .const headName headLevels =>
        let env ← getEnv
        match env.find? headName with
        | some (.inductInfo inductiveInfo) =>
          if visited.contains headName then
            return {
              node := unknownNode userName binderType binderKind #[.cycleTruncated]
              unknownsOccurred := true
              cyclesTruncated := true
            }
          let typeArgs := binderType.getAppArgs
          if inductiveInfo.numParams ≤ typeArgs.size then
            let params := typeArgs.extract 0 inductiveInfo.numParams
            let nextVisited := visited.push headName
            try
              let mut acc : ChildSummary := {}
              for ctorName in inductiveInfo.ctors do
                let ctorApp := mkAppN (Lean.mkConst ctorName headLevels) params
                let ctorFieldsType ← inferType ctorApp
                let ctorSummary : ChildSummary ←
                  forallTelescope ctorFieldsType fun fieldFVars _ => do
                    let mut summary : ChildSummary := {}
                    let mut fieldIndex := 0
                    for fieldFVar in fieldFVars do
                      let localDecl ← fieldFVar.fvarId!.getDecl
                      let fieldType ← inferType fieldFVar
                      let fieldTypeCore ← whnfCore fieldType
                      if fieldTypeCore == binderType then
                        -- Recursive occurrence of the scanned inductive:
                        -- its content is covered by the surrounding scan.
                        fieldIndex := fieldIndex + 1
                        continue
                      let fieldLabel :=
                        constructorFieldLabel ctorName localDecl.userName fieldIndex
                      let fieldResult ← inspectNode transparencyMode fuel nextVisited
                        fieldLabel fieldType (surfaceBinderKindOf localDecl.binderInfo)
                      let keepChild :=
                        childContributesAssumption fieldResult.node ||
                          childBlocksClassification fieldResult.node
                      summary := {
                        children :=
                          if keepChild then summary.children.push fieldResult.node
                          else summary.children
                        unknownsOccurred :=
                          summary.unknownsOccurred || fieldResult.unknownsOccurred
                        cyclesTruncated :=
                          summary.cyclesTruncated || fieldResult.cyclesTruncated
                      }
                      fieldIndex := fieldIndex + 1
                    pure summary
                acc := {
                  children := acc.children ++ ctorSummary.children
                  unknownsOccurred := acc.unknownsOccurred || ctorSummary.unknownsOccurred
                  cyclesTruncated := acc.cyclesTruncated || ctorSummary.cyclesTruncated
                }
              headRecognized := true
              children := acc.children
              unknownsOccurred := acc.unknownsOccurred
              cyclesTruncated := acc.cyclesTruncated
            catch _ =>
              headRecognized := false
        | some (.quotInfo quotInfo) =>
          match quotInfo.kind with
          | .type =>
            match binderType.getAppArgs[0]? with
            | some payloadType =>
              let payloadResult ← inspectNode transparencyMode fuel visited
                `payload payloadType .explicit
              let keepChild :=
                childContributesAssumption payloadResult.node ||
                  childBlocksClassification payloadResult.node
              headRecognized := true
              children := if keepChild then #[payloadResult.node] else #[]
              unknownsOccurred := payloadResult.unknownsOccurred
              cyclesTruncated := payloadResult.cyclesTruncated
            | none => pure ()
          | _ => pure ()
        | _ =>
          -- Unexpanded definitions, theorems, axioms, opaque constants,
          -- constructors, and recursors are not positively recognizable as
          -- data under the current transparency mode.
          pure ()
      | .forallE .. =>
        let codomainResult ← forallTelescope binderType fun _ codomain =>
          inspectNode transparencyMode fuel visited `codomain codomain .explicit
        let keepChild :=
          childContributesAssumption codomainResult.node ||
            childBlocksClassification codomainResult.node
        headRecognized := true
        children := if keepChild then #[codomainResult.node] else #[]
        unknownsOccurred := codomainResult.unknownsOccurred
        cyclesTruncated := codomainResult.cyclesTruncated
      | _ => pure ()
    else
      -- Direct propositions and proof-carrying wrappers with non-structure
      -- heads classify from their evidence alone.
      headRecognized := true
    let mut secondaryFlags : Array AssumptionFlag := #[]
    if evidence.binderTypeIsProp then
      secondaryFlags := secondaryFlags.push .binderTypeIsProp
    if evidence.binderQuantifiesOverProp then
      secondaryFlags := secondaryFlags.push .binderQuantifiesOverProp
    if binderKind == .instanceImplicit then
      secondaryFlags := secondaryFlags.push .instanceBinder
    let mut primaryCategory := AssumptionCategory.pureData
    if binderKind == .instanceImplicit then
      -- Instance binders stay `typeclass_assumption`, but an unrecognized
      -- instance head must still surface as an explicit unknown child so
      -- that policy cannot silently approve content the engine never saw.
      if !headRecognized then
        children := #[unknownNode `head binderType .explicit]
        unknownsOccurred := true
      primaryCategory := .typeclassAssumption
    else if evidence.contributes then
      primaryCategory := .directProp
    else if proofCarryingWrapper then
      primaryCategory := .proofCarryingData
    else if !headRecognized then
      unknownsOccurred := true
      primaryCategory := .unknown
    else if children.any childContributesAssumption then
      primaryCategory :=
        if isStructApp then .packageWithPropFields else .proofCarryingData
    else if children.any childBlocksClassification then
      unknownsOccurred := true
      primaryCategory := .unknown
    else
      primaryCategory := .pureData
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
      let summary ← inspectNode transparencyMode maxExpansionDepth #[] localDecl.userName
        localDecl.type binderKind
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
