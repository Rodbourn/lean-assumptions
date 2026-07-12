# Contributing

Read `AGENTS.md` first. It is the sole authoritative project charter; nothing
below overrides it.

## The short version

- This repository is run like infrastructure. Its product is a trustworthy
  `pass`/`fail` verdict; misclassification bugs are correctness incidents.
- Every change lands with its tests in the same change (charter TD-001), and
  every bug fix lands with a permanent regression test (TD-002).
- All verification gates must be green locally before a commit. The gates are
  the explicit steps in `.github/workflows/ci.yml`: `lake build`, `lake test`,
  `lake lint`, `lake env leanchecker --fresh LeanAssumptions`, the
  `python3 scripts/check_*.py` validators, and the CLI smoke test.
- Never weaken a gate to make it pass. Golden files, the coverage ledger, and
  performance references may be regenerated only together with the change that
  justifies them.

## Trusted core vs support layers

`LeanAssumptions/Core` and `LeanAssumptions/Policy` are the trusted core:
smallest possible, no `axiom`/`opaque`/`unsafe`/`extern`/`@[implemented_by]`/
`native_decide` (charter HR-001), conservative failure modes (`unknown` is a
result; silent optimism is not), and the strictest review. Everything else is
a support layer and must not be able to silently change trusted-core results.

## Landing a change

1. Classify the change: trusted core, public API (schemas, flags, command
   names — see `docs/compatibility-policy.md`), support layer, tests, or docs.
2. Write the failing test first, or land tests in the same change.
3. Keep `docs/requirements-status.md` honest: status rows change only with
   evidence, in the same commit as the change that justifies them.
4. Add a `CHANGELOG.md` entry for any public behavior change.
5. New public declarations need `schema/coverage-ledger.json` entries; the
   ledger gate diffs the ledger against the emitted public-surface inventory,
   so `lake test` must run before `check_coverage_ledger.py`.
6. Regenerate goldens only for justified output changes; golden comparisons
   also re-run at test-driver runtime, so stale snapshots fail loudly.
7. Use conventional commits (`type(scope): lowercase summary`) matching the
   existing history. Do not add AI-agent attribution lines to commits.
8. Pull requests require review before merge to the default branch.

## Reporting bugs

Use the misclassification issue template with a minimal reproducer, exact
toolchain, command, observed output, and expected conservative behavior. For
anything that could mislead certification users, use private vulnerability
reporting instead (see `SECURITY.md`).
