# lean-assumptions

## Authority

This file is the single authoritative charter for the `lean-assumptions` project.

- Tooling- or workflow-specific instruction files may add operational detail, but they may not weaken this charter.
- If any document conflicts with this file, this file wins.

The point of this repository is not merely to ship a useful command. The point is to ship a tool that a skeptical Lean engineer can read, test, audit, and trust for the specific claims it makes.

## Mission

`lean-assumptions` is a general Lean 4 package for auditing theorem assumption surfaces.

Lean already answers one question well:

- `#print axioms` answers: which axioms does this declaration transitively depend on?

This project addresses a different question:

- What assumptions are present in the elaborated theorem statement itself, after following binders, packages, structures, classes, aliases, and proof-carrying data?

The tool must make it easy to answer, with rigor:

- Does theorem `T` depend on direct `Prop` hypotheses?
- Does `T` hide assumptions inside a structure or class argument?
- Does `T` depend on proof-carrying data such as `Subtype`, `Sigma`, or nested packages with proposition fields?
- Which assumptions are explicit, implicit, instance-implicit, or packaged?
- Which assumptions are permitted by a project policy, and which are not?

This repository must remain fully agnostic to any one downstream project. It is a community tool first.

## Problem Statement

Lean's built-in proof-validation stack is strong, but each layer answers a distinct question:

- editor check marks / `lake build`: the theorem elaborates and the kernel accepted a proof
- `#print axioms`: the theorem's proof term and dependencies use only certain axioms
- `leanchecker`: replay stored declarations through the kernel
- `comparator`: compare a trusted challenge theorem against an untrusted solution in a sandbox, optionally with additional kernels

Those tools do not, by themselves, fully classify the theorem statement's assumption surface.

In particular, a theorem may be axiom-clean while still depending on extra assumptions passed through:

- direct `Prop` binders
- proposition-valued structure fields
- proof-carrying data fields
- typeclass arguments
- aliases that hide any of the above

`lean-assumptions` exists to inspect that theorem surface mechanically and conservatively.

## Design Basis

This project is grounded in current Lean and community practice. The implementation and documentation must stay aligned with the following sources and the engineering expectations they imply.

Primary Lean references:

- Lean Language Reference, `Axioms`
  - <https://lean-lang.org/doc/reference/latest/Axioms/>
- Lean Language Reference, `Validating a Lean Proof`
  - <https://lean-lang.org/doc/reference/latest/ValidatingProofs/>
- Lean API docs, `Lean.Declaration`
  - <https://lean-lang.org/doc/api/Lean/Declaration.html>
- Lean API docs, `Lean.Expr`
  - <https://lean-lang.org/doc/api/Lean/Expr.html>
- Lean API docs, `Lean.Structure`
  - <https://lean-lang.org/doc/api/Lean/Structure.html>
- Lean Language Reference, `Lake`
  - <https://lean-lang.org/doc/reference/latest/Build-Tools-and-Distribution/Lake/>

Adjacent Lean tools and norms:

- `leanprover/comparator`
  - <https://github.com/leanprover/comparator>
- bundled `leanchecker` / archived `lean4checker`
  - <https://github.com/leanprover/lean4checker>
- `leanprover/doc-gen4`
  - <https://github.com/leanprover/doc-gen4>
- `leanprover/lean-action`
  - <https://github.com/leanprover/lean-action>
- mathlib documentation and style guidance
  - <https://leanprover-community.github.io/contribute/doc.html>
  - <https://leanprover-community.github.io/contribute/style.html>
  - <https://leanprover-community.github.io/contribute/naming.html>

Important caution that must inform the design:

- Lean issue `#8840` documents that `Lean.collectAxioms` / `#print axioms` historically missed axioms referenced only through axiom types.
  - <https://github.com/leanprover/lean4/issues/8840>

This is one reason `lean-assumptions` must be explicit about what it audits and must not pretend that built-in axiom reporting already solves statement-surface analysis.

## Non-Negotiable Principles

1. The tool must never overclaim.
2. Any ambiguity in classification must resolve conservatively.
3. Unknown is an allowed result. Silent optimism is not.
4. The core classification engine must be small, explicit, and readable.
5. The project must prefer `Std`-only dependencies unless there is a compelling technical reason otherwise.
6. The core logic must not rely on `axiom`, `constant`, `opaque`, `unsafe`, FFI, or native evaluation shortcuts.
7. Any trusted boundary must be named in the documentation and in machine-readable output.
8. Every bug fix must land with a regression test.
9. No feature is complete until its output, limitations, and failure modes are documented.
10. "Looks right" is not an acceptance criterion anywhere in this repository.

## Threat Model

The repository must be designed against three threat levels and must name them plainly.

### Level 1: Honest author, ordinary review

Goal:

- explain what assumptions a theorem really takes

Protection expected:

- correct binder peeling
- correct structure/class expansion
- usable human output
- usable JSON for CI

### Level 2: Skeptical reviewer

Goal:

- detect assumptions hidden in packaging, aliases, instances, and proof-carrying data

Protection expected:

- recursive package expansion
- binder-kind reporting
- raw elaborated type output
- notation-resistant views
- policy checks with deterministic results

### Level 3: Adversarial presentation

Goal:

- reduce the chance that custom notation, aliases, or packaging makes a theorem appear stronger than it is

Protection expected:

- show the elaborated declaration type
- offer a normalized assumption tree
- distinguish theorem statement meaning from proof validity
- clearly direct users to `#print axioms`, `leanchecker`, and `comparator` for the problems those tools solve better

This tool is not a sandbox, not an external checker, and not a theorem-statement equivalence checker. It must say so repeatedly and plainly.

## Product Scope

### In Scope

- inspection of declaration types from a Lean environment
- peeling `forall` binders across explicit, implicit, strict implicit, and instance-implicit arguments
- classification of direct proposition assumptions
- recursive expansion of structures and classes
- detection of proof-carrying data patterns
- transparency-controlled alias expansion
- policy checking against user-supplied allowlists / denylists
- deterministic human reports
- deterministic JSON reports
- deterministic delta reports between prior and current JSON audit artifacts
- deterministic failure-cluster reports from JSON audit artifacts
- batch scanning of declarations and modules
- CI-friendly exit codes
- regression corpus for tricky theorem-surface shapes

### Out of Scope

- proving that the theorem matches an informal English claim
- replacing `#print axioms`
- replacing `leanchecker`
- replacing `comparator`
- sandboxing malicious Lean code
- inferring what assumptions "should have been" present
- rewriting downstream theorem statements automatically
- project-specific remediation heuristics, theorem suggestions, or cleanup advice

## Core Claim

If `lean-assumptions` reports a declaration under a stated policy and transparency mode, then it guarantees only this:

- it inspected the elaborated declaration type available in the Lean environment,
- it classified binders and recursively expanded supported package forms according to the documented rules,
- it emitted a deterministic report of the resulting assumption surface,
- and it evaluated that report against the configured policy.

It does not guarantee:

- that the theorem means what a human reader informally expects,
- that the theorem uses no hidden axioms,
- that imported libraries are honest,
- or that a malicious build environment has not already been compromised.

The documentation and command output must keep this distinction visible.

## Success Criteria

The project succeeds only if a serious Lean user can use it to answer, for a target theorem:

1. what binders the theorem takes
2. which of those binders are direct propositions
3. which binders are packages that themselves carry propositions
4. which assumptions are instance-driven
5. which assumptions are proof-carrying data rather than bare propositions
6. what the normalized assumption tree is
7. whether the theorem passes a stated policy
8. under exactly what transparency and expansion rules that result was obtained

## Architectural Requirements

The implementation must be split into small, auditable layers.

### Layer A: Core classification

Pure or near-pure classification logic over elaborated declaration types.

Responsibilities:

- declaration lookup
- binder peeling
- binder-kind classification
- recursive expansion
- cycle detection
- normalization into an internal report model

This layer is the heart of the tool and must be the most heavily tested code in the repository.

### Layer B: Policy engine

Responsibilities:

- allowlist / denylist evaluation
- severity classification
- failure and warning rules
- conservative treatment of unknown nodes

This layer must be completely deterministic.

### Layer C: Rendering

Responsibilities:

- stable human-readable report
- stable machine-readable JSON
- stable delta and summary renderers

Renderer bugs must not affect core classification decisions.

### Layer D: Command and CLI adapters

Responsibilities:

- custom `#print ...` commands
- executable entry points
- module scan orchestration
- exit codes for CI

Adapters may use IO. They must stay thin.

## Trusted Core Boundary

The repository must distinguish between:

- the trusted classification core
- convenience adapters and developer tooling

The trusted classification core is:

- `LeanAssumptions/Core`
- `LeanAssumptions/Policy`

These modules are where the repository's core correctness claims live. They receive the strongest restrictions, the strongest tests, and the strictest review.

The following are support layers, not the trusted core:

- `LeanAssumptions/Render`
- `LeanAssumptions/Delta`
- `LeanAssumptions/Cluster`
- `LeanAssumptions/Baseline`
- `LeanAssumptions/Command`
- `LeanAssumptions/Cli`
- `LeanAssumptions/JsonUtil`
- docs, scripts, and CI wrappers

Support layers may fail, but they must not be able to silently change core classification results.

## Required Repository Layout

The repository should converge toward this structure:

```text
lean-assumptions/
  CHARTER.md
  README.md
  LICENSE
  lean-toolchain
  lakefile.lean
  LeanAssumptions.lean
  LeanAssumptions/
    Core/
    Policy/
    Render/
    Command/
    Cli/
    Version.lean
  LeanAssumptionsTest/
    Unit/
    Integration/
    Golden/
    Fixtures/
    Performance/
  docs/
  docbuild/
  scripts/
  schema/
  .github/workflows/
```

`Fixtures/` is the only place where intentionally suspicious Lean constructs may appear for testing.

## Functional Requirements

### FR-001: Declaration inspection

The tool must inspect any named declaration visible in the current environment and recover:

- declaration name
- declaration type
- declaration kind when useful (`theorem`, `def`, `opaque`, `axiom`, etc.)

### FR-002: Binder peeling

For each declaration under audit, the tool must peel all outer `forall` binders and record:

- binder name
- binder type
- binder kind:
  - explicit
  - implicit
  - strict implicit
  - instance implicit

### FR-003: Direct proposition detection

If a binder type is itself a proposition, the tool must classify it as a direct proposition assumption.

### FR-004: Structure and class expansion

If a binder type is a structure or class application, the tool must recursively inspect its fields and detect:

- proposition-valued fields
- proof-carrying data fields
- nested structures/classes with either of the above

### FR-005: Proof-carrying data detection

The tool must classify common proof-carrying data patterns, including at minimum:

- `Subtype`
- `Sigma`
- `PSigma`
- structures with proposition fields
- structures whose fields recursively contain proposition-bearing subterms

The project may classify further forms over time, but these are not optional.

### FR-006: Alias transparency policy

The tool must support documented expansion modes for aliases and wrappers, with the chosen mode reported in every output artifact.

At minimum, it must distinguish:

- no expansion beyond the declaration type as given
- reducible / abbreviation expansion
- project-defined recursive normalization

If classification depends materially on transparency, output must say so.

### FR-007: Cycle detection

Recursive expansion must be cycle-safe.

Requirements:

- no infinite recursion
- cycles reported explicitly
- conservative policy result when cycle handling leaves unknowns

### FR-008: Deterministic tree output

The tool must produce a normalized assumption tree with stable ordering independent of hash-map iteration or incidental elaboration order.

### FR-009: Human-facing commands

The initial command surface must include:

- `#print assumptions <decl>`
- `#print assumption_tree <decl>`
- `#print assumption_json <decl>`

Names may evolve only for strong community reasons. Backward compatibility policy must be documented.

### FR-010: CLI

The repository must ship an executable that can:

- inspect one declaration
- inspect a list of declarations
- inspect declarations from a module
- emit text or JSON
- return nonzero exit codes on policy failure or audit failure

### FR-011: Policy files

The CLI must accept a machine-readable policy file. The policy format must be versioned and documented.

Minimum policy features:

- permit direct proposition binders by name or pattern
- permit packaged assumptions by type name
- configure treatment of instance arguments
- configure unknown handling
- configure transparency mode

Exact-name matching should be the default. Broader patterns must be explicit and auditable.

### FR-012: Conservative failure mode

If the tool cannot classify a binder or expansion path soundly under its documented rules, it must emit `unknown` and fail policy unless the policy explicitly allows unknowns.

### FR-013: Raw theorem-surface visibility

The tool must offer a notation-resistant view of the declaration type, using fully qualified names where feasible, so that users can audit statement meaning rather than relying only on surface syntax.

### FR-014: Batch summaries

The CLI must provide machine-readable summaries for repository-scale CI use, including counts of:

- declarations scanned
- declarations passed
- declarations failed
- declarations with unknown nodes
- policy and schema versions

### FR-015: Stable JSON

JSON output is part of the public API and must:

- be versioned
- be deterministic
- carry tool version
- carry Lean version
- carry schema version
- carry transparency mode
- carry policy digest or identifier

### FR-016: Differential mode

The tool must support a repository-agnostic diff mode for comparing two JSON audit artifacts emitted by `lean-assumptions`.

At minimum, diff mode must:

- accept a prior/baseline artifact and a current artifact
- compare declarations by stable target name
- report declarations added to or removed from the compared artifact set
- report declarations whose policy result changed
- report declarations whose policy finding categories changed
- report declarations whose top-level boundary shape changed
- emit stable human-readable text
- emit versioned deterministic JSON
- state that it compares rendered audit artifacts only and does not re-run Lean elaboration, reclassify theorem surfaces, validate proof axioms, sandbox execution, or infer how a project should remediate failures

Diff mode must remain support-layer functionality. It must not alter trusted core classification or policy semantics.

### FR-017: Failure clustering

The tool must support deterministic grouping of failing declarations by report-derived root-cause signatures.

The intended grouping inputs are generally applicable fields such as finding kind, finding category, package/typeclass/direct-proposition source, `type_name`, and module or lane metadata when present in public artifacts. It must not depend on downstream project names, custom theorem families, or private cleanup heuristics.

At minimum, clustering must:

- accept a single-report or batch JSON artifact emitted by `lean-assumptions`
- consider `fail` and `audit_error` declarations failing declarations
- group failing findings by finding kind, finding category, source class, `type_name`, and module/lane metadata when present
- use `unknown` or `null` for grouping fields that are absent from the public artifact rather than inferring project-specific meaning
- emit declarations within each cluster in stable target-name order
- emit clusters in deterministic order by descending declaration count, then signature
- emit stable human-readable text
- emit versioned deterministic JSON
- state that it clusters rendered audit artifacts only and does not re-run Lean elaboration, validate proof axioms, sandbox execution, prove theorem-statement equivalence, or suggest remediation

Failure clustering must remain support-layer functionality. It must not alter trusted core classification or policy semantics.

### FR-018: Hidden-vs-explicit remediation signals

The roadmap must include a report-derived classification that distinguishes hidden package/data-wrapper failures, explicit direct-proposition failures, explicit typeclass-assumption failures, and mixed failures.

This signal must be inferred mechanically from public report structure and policy findings. It must not guess user intent or suggest theorem rewrites.

### FR-019: Priority and trend summaries

The roadmap must include deterministic summaries for iterative assumption-surface cleanup, including largest remaining hidden-package families, explicit direct-proposition families, compact CI trend artifacts, per-lane counts when lane metadata is present, and deltas from a supplied baseline artifact.

These summaries must be based only on public audit artifacts and must remain conservative when artifact fields are missing or unsupported.

## Classification Rules

The classifier must be explicit about categories. At minimum, every node in the report must belong to one of:

- `pure_data`
- `direct_prop`
- `proof_carrying_data`
- `package_with_prop_fields`
- `typeclass_assumption`
- `alias`
- `unknown`

If a node fits multiple categories, the report must preserve both a primary classification and secondary flags where useful.

The exact classification lattice belongs in code and docs, but the public categories above are mandatory.

## Policy Semantics

Policy results must distinguish at least:

- `pass`
- `warn`
- `fail`
- `audit_error`

Unknowns must never be silently downgraded to pass.

The policy engine must support a strict mode in which any of the following is a failure:

- unknown node
- cycle truncation
- unapproved direct proposition
- unapproved package with proposition fields
- unapproved typeclass assumption
- unsupported wrapper or alias that blocks analysis

## Security and Hardening Requirements

### HR-001: Minimal trusted core

The core classification and policy modules must avoid:

- `axiom`
- `constant`
- `opaque`
- `unsafe`
- `extern`
- `@[implemented_by]`
- `native_decide`

If any exception is absolutely necessary outside the core, it must be isolated, documented, and justified in both code and release notes.

### HR-002: No silent fallback

No adapter may silently fall back from a stricter mode to a weaker mode. Every fallback must be explicit in output.

### HR-003: No network dependence

The runtime audit path must not depend on network access.

### HR-004: Reproducible reports

Given the same Lean version, repository state, policy file, and command invocation, output must be byte-stable apart from documented timestamp fields, which should be avoided unless necessary.

### HR-005: Honest limitations

Every command and README section describing assurances must also name what is not being assured.

## Performance Requirements

This tool is for real projects, not toy examples.

Requirements:

- single-declaration inspection should feel interactive on ordinary theorem statements
- module scans must be incremental where practical
- large scans must stream or chunk output rather than requiring all results to remain resident unnecessarily
- performance regressions must be tracked with dedicated benchmarks on representative fixtures

Performance may not be improved by weakening classification or hiding unknowns.

## Documentation Requirements

The repository must be exemplary by Lean community standards.

Requirements:

- every public definition and major theorem must have a docstring
- every source file must have a meaningful module docstring
- every command must be documented with examples
- the README must explain:
  - the problem the tool solves
  - the problems it does not solve
  - how it relates to `#print axioms`, `leanchecker`, and `comparator`
  - how policy files work
  - how to integrate the tool into CI
- API docs must build with `doc-gen4`

The docs must be concise, exact, and free of marketing language.

## Style Requirements

The codebase must follow Lean community expectations first, then adjacent static-analysis best practice.

### Lean-specific

- use mathlib-style naming conventions unless there is a strong local reason otherwise
- keep declarations top-level and visually readable
- provide explicit argument and return types on public declarations
- keep module imports minimal
- keep adapter logic thin

### Static-analysis-specific

- separate parsing / extraction / normalization / policy / rendering
- prefer typed internal data structures over ad hoc strings
- version public schemas
- make failures diagnosable
- keep logs and reports deterministic

## Testing Doctrine

This repository is test-driven. Not aspirationally, but operationally.

No implementation work is accepted unless the tests that justify it already exist or land in the same change.

### TD-001: Test-first rule

Every new feature starts with:

- a concrete behavioral spec
- one or more failing tests
- then implementation

### TD-002: Regression rule

Every bug fix must include:

- a minimal reproducer
- a permanent regression test
- a note in the changelog if public behavior changed

### TD-003: Layered test suite

The repository must maintain all of:

- unit tests for classification primitives
- unit tests for policy rules
- integration tests for commands and CLI
- golden tests for human and JSON output
- fixture tests for adversarial and tricky theorem surfaces
- performance tests

### TD-004: Coverage obligation

This project adopts a stronger rule than ordinary coverage percentages.

Every non-generated line in the repository must be covered by at least one automated test, and every public behavior must be covered by both:

- a direct test near the feature
- an end-to-end test through the public interface

If Lean-native coverage tooling is insufficient, the repository must maintain:

- a machine-readable coverage ledger mapping files and public functions to tests
- CI checks that the ledger is complete and in sync

If workable line or branch coverage tooling becomes available, CI must enforce:

- 100% line coverage for `LeanAssumptions/Core` and `LeanAssumptions/Policy`
- no less than 95% line coverage repository-wide

These numbers are floors, not aspirations.

### TD-005: Required fixture corpus

The test corpus must include, at minimum:

- direct proposition binders
- implicit proposition binders
- instance-implicit proposition-bearing classes
- plain data binders
- structures with direct proposition fields
- nested packages with proposition fields
- `Subtype`
- `Sigma`
- `PSigma`
- reducible aliases hiding packages
- theorem statements with no proposition-bearing assumptions
- cyclic or self-referential structure graphs
- declarations intentionally using suspicious constructs in fixtures only
- examples showing the distinction between proof validity and statement-surface assumptions

### TD-006: Golden output stability

The repository must maintain golden files for:

- text output
- JSON output

Output changes require intentional snapshot updates and review.

## Verification Gates

No pull request is mergeable unless all of the following pass:

1. `lake build`
2. `lake test`
3. `lake lint`
4. `lake env leanchecker --fresh LeanAssumptions`
5. JSON schema validation tests
6. golden output tests
7. coverage-ledger validation
8. docs build
9. cross-platform CI where configured

For releases, add:

10. Reservoir eligibility check
11. release artifact sanity check
12. changelog and schema-version review

## CI and Release Requirements

### CI

The repository must use GitHub Actions and Lean community tooling where it helps rather than inventing local replacements.

At minimum:

- use `leanprover/lean-action`
- run explicit `build`, `test`, `lint`, and `leanchecker`
- run on `ubuntu-latest`
- add `macos-latest` and `windows-latest` once the CLI is present
- run a scheduled compatibility job against the current Lean release candidate

### Update discipline

The repository should adopt an automated Lean upgrade workflow, such as `lean-update`, or an equivalent scheduled update pipeline.

### Release discipline

- tag releases semantically
- publish schema versions
- publish compatibility notes for supported Lean versions
- keep Reservoir metadata correct
- do not cut a release with known misclassification bugs in trusted cores

## Compatibility Policy

The repository should support:

- the latest Lean stable release
- the current Lean release candidate once practical

Compatibility claims must be tested in CI, not inferred.

If a Lean API change forces a semantic change in reports, the repository must bump the schema or report format version accordingly.

## Public API Policy

The following are public APIs and require compatibility discipline:

- command names
- CLI flags
- JSON schema
- policy-file schema

Human-readable text formatting may evolve more freely, but only if:

- changes are documented
- golden files are reviewed
- JSON remains stable

## Governance and Disclosure

This repository should be run like infrastructure, not like a scratch tool.

Requirements:

- use a standard open-source license compatible with Lean ecosystem norms, preferably Apache-2.0
- require review before merge to the default branch
- treat misclassification bugs as correctness incidents, not cosmetic defects
- maintain a changelog that records public behavior changes
- maintain a security or disclosure policy for bugs that could materially mislead certification users
- do not silently change policy semantics in patch releases

## Output Requirements

Every report artifact, human or machine, must state:

- tool version
- Lean version
- schema version
- target declaration
- transparency mode
- policy identifier or digest
- whether unknowns occurred
- whether cycles were truncated

This is required so that reports can be cited and reproduced later.

Delta artifacts compare two report artifacts and must state the same metadata
for both baseline and current inputs where present. They must also state the
delta schema version and the limitation that no Lean re-elaboration or proof
validation was performed during comparison.

Cluster artifacts summarize one report artifact and must state the source
artifact metadata where present. They must also state the cluster schema version
and the limitation that no Lean re-elaboration, proof validation, or remediation
inference was performed during clustering.

## Community Value Requirements

This repository should be something the Lean community would reasonably want to adopt, not merely tolerate.

To that end:

- keep the dependency footprint small
- do not require mathlib for the core package
- provide good docs and examples on plain `Init` / `Std`
- keep installation ordinary via Lake
- support Reservoir publication
- write issue templates that demand minimal repros
- publish limitations and threat model up front

## Working Rules for Contributors

Anyone — or anything — making changes in this repository must follow these rules.

1. Read this file first.
2. Do not weaken the trust story to ship faster.
3. Prefer the smallest implementation that satisfies the current test and spec.
4. When a feature touches the public report model or policy semantics, update docs, schema notes, and tests in the same change.
5. Do not merge TODO-shaped behavior into the trusted core.
6. Do not introduce cleverness where a direct structural traversal will do.
7. Do not add dependencies lightly.
8. Do not hide ambiguity; surface it.
9. If you cannot classify something rigorously, return `unknown`.
10. If a requirement here is impossible under current Lean APIs, document the gap and tighten the requirement around what is actually checkable. Do not quietly omit it.

## Initial Roadmap

### Phase 0: Repository skeleton and charter

Deliverables:

- authoritative `CHARTER.md`
- initial package skeleton
- CI skeleton

### Phase 1: Core report model and fixture corpus

Deliverables:

- internal report data types
- binder peeling
- synthetic fixtures for all required binder kinds
- failing tests for core classifications

### Phase 2: Recursive expansion and policy engine

Deliverables:

- structure/class expansion
- proof-carrying data detection
- cycle handling
- strict policy evaluation

### Phase 3: Commands, CLI, JSON schema, docs

Deliverables:

- `#print assumptions`
- `#print assumption_tree`
- `#print assumption_json`
- CLI executable
- versioned JSON schema
- README and API docs

### Phase 4: Hardening and release

Deliverables:

- cross-platform CI
- `leanchecker --fresh`
- Reservoir readiness
- scheduled upgrade workflow
- performance baseline
- first tagged release

No phase is complete until its gates pass.

## Definition of Done

A feature or milestone is done only when all of the following are true:

1. the behavior is specified
2. tests exist and pass
3. failure modes are conservative
4. docs explain the behavior and its limits
5. CI exercises the change
6. no requirement in this file was silently weakened to make it pass

Anything less is not done.
