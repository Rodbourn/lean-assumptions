# Audit finding issue drafts

Ready-to-paste GitHub issue bodies for the six fixed defects from
[the 2026-07-11 audit](audit-2026-07-11.md), so the findings have visible,
linkable history. File each with the `bug` label, then close it immediately
with a comment referencing its fix commit. Delete this file once filed.

---

**Title:** Unrecognized binder head shapes classified as pure_data and passed strict policy

Statements carrying a proof of `0 = 1` through a `let`-wrapped type, a
non-structure inductive constructor field, or a function codomain reported
`policy_result: pass` under strict policy. Minimal reproducer and analysis:
docs/audit-2026-07-11.md, finding 1. **Fixed by 2cbfc44** (classification by
positive head recognition; unrecognized heads are `unknown`), regression
fixtures in `LeanAssumptionsTest/Fixtures/Adversarial.lean`.

---

**Title:** Alias detection matched only abbrev hints; def-based aliases hid packages

`def` and `@[reducible] def` wrappers around proposition-carrying packages
were not detected as aliases and classified optimistically. Finding 2 in
docs/audit-2026-07-11.md. **Fixed by 4a2c37e** (every unfoldable definition
head reports `alias`).

---

**Title:** Declaration surface never audited: alias-hidden statements reported zero binders

`theorem t : HiddenStatement` where `HiddenStatement` is an alias for a
quantified statement passed strict policy with an empty assumption tree.
Finding 3 in docs/audit-2026-07-11.md. **Fixed by 9783269** (round-by-round
peeling; blocked remainders become a policy-visible `result` surface node).

---

**Title:** Nested same-head generics falsely failed as truncated cycles

`(p : Nat × Nat × Nat)` failed strict policy as a cycle because cycle
detection keyed on head names. Finding 4 in docs/audit-2026-07-11.md.
**Fixed by 7b43929** (instance-keyed cycle detection).

---

**Title:** Transparency-mode labels misdescribed the reductions actually applied

`reducible` mode reduced at default transparency and
`recursive_normalization` was not operationally distinct. Finding 5 in
docs/audit-2026-07-11.md. **Fixed by 995dd1b** (mode-pinned reduction sites,
`transparency_limited` artifact signal).

---

**Title:** Artifacts reported CLI-weakened policies under the strict label

`--allow-*` flags weakened the evaluated policy while artifacts still said
`policy_identifier: strict`. Finding 6 in docs/audit-2026-07-11.md.
**Fixed by 0d4cb5d** (modifications recorded in the identifier; label-
independent `policy_digest`).
