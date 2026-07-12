# Pull Request

## What changed and why

<!-- One paragraph. Name the requirement (FR-xxx / HR-xxx / TD-xxx) or issue this serves. -->

## Change classification

- [ ] Trusted core (`LeanAssumptions/Core`, `LeanAssumptions/Policy`) — strictest review
- [ ] Public API (schemas, CLI flags, command names) — see `docs/compatibility-policy.md`
- [ ] Support layer / tests / docs / CI

## Checklist

- [ ] Tests land in this change (TD-001); bug fixes include a permanent regression test (TD-002)
- [ ] All CI gates green; nothing was weakened to pass
- [ ] Goldens/ledger/performance references regenerated only with the change that justifies them
- [ ] `docs/requirements-status.md` and `CHANGELOG.md` updated where behavior or status changed
- [ ] For trusted-core changes: conservative failure modes preserved (`unknown`, never silent optimism); HR-001 prohibitions respected
- [ ] No AI-agent attribution in commit messages
