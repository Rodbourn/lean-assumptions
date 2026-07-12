# Golden Output

Golden text and JSON snapshots exercise the public rendering contract.

Current snapshots:

- `packageBinder.txt`: human-readable report for a strict-policy package failure
- `packageBinder.json`: JSON report for the same audited declaration
- `packageBinder-batch.json`: batch JSON report for the same audited declaration
- `delta-baseline.json`: batch JSON fixture used as the prior delta input
- `delta-current.json`: batch JSON fixture used as the current delta input
- `delta-report.txt`: human-readable delta report for the fixture comparison
- `delta-report.json`: JSON delta report for the fixture comparison
- `cluster-input.json`: batch JSON fixture used as the clustering input
- `cluster-report.txt`: human-readable failure-cluster report for the fixture
- `cluster-report.json`: JSON failure-cluster report for the fixture
- `Baseline/empty-batch.json`: empty v1 batch artifact used for baseline pass,
  regression, and improvement comparisons
- `Baseline/pass-output.txt`: human-readable baseline pass report
- `Baseline/regression-output.txt`: human-readable baseline regression report
- `Baseline/improvement-output.txt`: human-readable baseline improvement report

Snapshots that would embed the live toolchain's `Lean.versionString` store
the placeholder token `<LEAN_VERSION>` instead; golden comparisons (compile
time, test-driver runtime, and `scripts/check_examples.py`) normalize exactly
those bytes in the ACTUAL output before comparing, so one golden set validates
every toolchain in the compatibility matrix. Emitted artifacts always carry
the real version — the token exists only in checked-in expectations. When
regenerating goldens, substitute the current version string with the token as
the final step. Any non-version byte drift on a new toolchain still fails the
golden gates by design.

JSON snapshots are also validated against `schema/report-v1.schema.json` and
`schema/batch-report-v1.schema.json`, including nested baseline fixtures; delta
snapshots are validated against `schema/delta-report-v1.schema.json`; cluster
snapshots are validated against `schema/cluster-report-v1.schema.json` by
`python scripts/check_report_schema.py`.
