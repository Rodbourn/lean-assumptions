import LeanAssumptionsTest.TestUtil

/-!
Unit tests for toolchain-byte normalization in golden comparisons.

`normalizeToolchainBytes` replaces exact occurrences of the live
`Lean.versionString` with `leanVersionToken` so a single golden set validates
every toolchain in the compatibility matrix. These tests pin the contract:
every exact occurrence is replaced, nothing else is touched, and the
normalization is idempotent on already-tokenized golden text.
-/

open LeanAssumptionsTest

run_cmd do
  assertEq "live version normalizes to the token"
    s!"lean_version: {leanVersionToken}"
    (normalizeToolchainBytes s!"lean_version: {Lean.versionString}")
  assertEq "every occurrence is replaced"
    s!"\{\"lean_version\":\"{leanVersionToken}\"} {leanVersionToken}"
    (normalizeToolchainBytes s!"\{\"lean_version\":\"{Lean.versionString}\"} {Lean.versionString}")
  assertEq "version-unlike strings are untouched"
    "lean_version: 9.9.9-rc9 decl_v9_9_9"
    (normalizeToolchainBytes "lean_version: 9.9.9-rc9 decl_v9_9_9")
  assertEq "idempotent on already-tokenized text"
    s!"lean_version: {leanVersionToken}"
    (normalizeToolchainBytes s!"lean_version: {leanVersionToken}")
  assertTrue "token never collides with a real version string"
    (!(leanVersionToken == Lean.versionString))
