# Security Policy

Misclassification bugs in the trusted core (`LeanAssumptions/Core`,
`LeanAssumptions/Policy`) are correctness incidents for this repository, not
cosmetic defects: a false `pass` can materially mislead downstream
certification and audit users.

## Reporting a vulnerability or misclassification

For any issue that could cause the tool to report an assumption surface as
cleaner than it is — a false `pass`, a silently dropped finding, an artifact
that misstates the policy or mode actually used — use GitHub's private
vulnerability reporting on this repository (Security tab → "Report a
vulnerability") rather than a public issue, so downstream users are not
exposed before a fix lands.

Include:

- a minimal Lean reproducer
- the exact Lean toolchain string (`lean-toolchain`)
- the command or test path used, including policy file and flags
- the observed report or output
- the expected conservative behavior

For issues with no misleading potential (crashes, usability, false failures
that are loud rather than silent), an ordinary public issue using the
misclassification template is welcome.

## Response commitments

- Acknowledgment within 7 days.
- Confirmed trusted-core misclassifications are fixed with a regression test
  before any new release is tagged; the charter forbids releasing with known
  misclassification bugs in trusted cores.
- Public disclosure after a fix is available, credited if desired, including a
  changelog entry and, when severity warrants, a note in the README's audit
  status section.

## Scope

In scope: the trusted classification and policy core, the renderers and CLI
insofar as they can misrepresent trusted-core results, and the published JSON
schemas. Out of scope: sandboxing hostile Lean code (explicitly a non-goal;
see CHARTER.md's threat model), and vulnerabilities in Lean or Lake themselves,
which belong upstream.
