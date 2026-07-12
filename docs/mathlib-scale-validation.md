# Mathlib-Scale Validation

This page records the first mathlib-scale validation run of `lean-assumptions`
and the exact procedure to reproduce or extend it. It validates the charter's
performance and conservatism requirements against real-world Lean code rather
than fixtures.

## Setup (reproducible)

Environment: WSL2, repository checkout at the run's HEAD, toolchain
`leanprover/lean4:v4.30.0-rc2`. Mathlib has a matching tag for this exact
toolchain, so its prebuilt oleans load directly.

```bash
mkdir lean-assumptions-scan && cd lean-assumptions-scan
printf 'leanprover/lean4:v4.30.0-rc2\n' > lean-toolchain
git clone --depth 1 --branch v4.30.0-rc2 \
  https://github.com/leanprover-community/mathlib4 mathlib4
cat > lakefile.lean <<'EOF'
import Lake
open Lake DSL

package «lean-assumptions-scan» where
  description := "Downstream mathlib-scale scan harness for lean-assumptions."

require mathlib from "./mathlib4"

require «lean-assumptions» from "../lean-assumptions"
EOF
lake update
lake exe cache get          # ~8,090 olean files
lake build lean-assumptions # builds the CLI inside this workspace
```

Mathlib is a dependency of this scratch workspace only. It is never a
dependency of `lean-assumptions` itself (charter: no mathlib in the core
package), and nothing mathlib-specific may leak into trusted-core or cluster
logic (FR-017).

## Scan procedure

```bash
lake exe lean-assumptions --module <Module> --scan-module <Module> --format json
```

Strict policy is the default; mathlib theorems legitimately take typeclass
and proposition binders, so nonzero exit (1) is the expected outcome — these
runs measure classifier behavior, performance, and determinism, not policy
cleanliness.

## Results (2026-07-11, run at repository revision `a38d4fd`)

| Module | Scanned | Passed | Failed | Unknown-bearing | Wall time |
| --- | --- | --- | --- | --- | --- |
| `Mathlib.Logic.Basic` | 357 | 41 | 316 | 0 | 6 m 43 s (cold) |
| `Mathlib.Order.Basic` | 428 | 19 | 409 | 2 | 5 m 18 s |
| `Mathlib.Algebra.Group.Basic` | 546 | 3 | 543 | 16 | 2 m 40 s |

Totals: **1,331 declarations scanned, zero crashes, correct exit codes.**

Interpretation notes:

- `--scan-module` enumerates every constant the environment attributes to the
  module, including auto-generated auxiliaries — counts are constants, not
  hand-written theorems.
- **Conservatism**: 18 of 1,331 declarations (1.4%) carry `unknown` nodes.
  Every sampled unknown is a type headed by a recursor application
  (`Nat.rec …`, from `Nat.rec`-defined auxiliary functions) or a stuck
  higher-order application (`IsTotal α (fun …)`), i.e. shapes outside the
  positively recognized set — the polarity invariant resolving them to
  `unknown` rather than optimistically to `pure_data`. No shape produced a
  silent optimistic classification.
- **Determinism**: re-running the `Mathlib.Logic.Basic` scan produced a
  byte-identical JSON artifact.
- **Trend analytics on real data**: clustering the `Algebra.Group.Basic`
  artifact yields the FR-018/FR-019 signals (356 explicit-typeclass, 186
  mixed, 1 explicit-direct-prop failing declarations) and names real hidden
  families (`Nat.rec`, `Function.LeftInverse`, `Function.Injective`, …).
- **Performance**: wall time is dominated by environment import from a
  WSL2 `/mnt/c` filesystem (user CPU ~3 s vs system ~28 s on the first
  scan — I/O-bound). Classification itself is a small fraction of wall
  time. Native filesystems and hosted runners are expected to be
  substantially faster; per-declaration classification cost at this scale
  showed no pathological cases.

## Boundaries stated plainly

- Single machine, single filesystem class (WSL2 `/mnt/c`); no hosted-runner
  timings yet.
- Three pinned modules (~1,331 constants), not all of mathlib. The procedure
  scales by listing more `--scan-module` values; a scheduled CI job over a
  pinned module set is the documented next step and belongs to the
  conservatism-at-scale campaign.
- The 18 unknown-bearing declarations were sampled, not exhaustively audited;
  all sampled cases are conservative (`unknown`), which is the designed
  failure direction.

## Re-verification

```bash
cd lean-assumptions-scan
lake exe lean-assumptions --module Mathlib.Logic.Basic \
  --scan-module Mathlib.Logic.Basic --format json > scan-a.json; echo $?
lake exe lean-assumptions --module Mathlib.Logic.Basic \
  --scan-module Mathlib.Logic.Basic --format json > scan-b.json
cmp scan-a.json scan-b.json && echo deterministic
lake exe lean-assumptions --cluster scan-a.json --format json | head -c 400
```
