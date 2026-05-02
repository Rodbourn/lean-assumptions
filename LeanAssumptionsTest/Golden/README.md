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

JSON snapshots are also validated against `schema/report-v1.schema.json` and
`schema/batch-report-v1.schema.json`; delta snapshots are validated against
`schema/delta-report-v1.schema.json`; cluster snapshots are validated against
`schema/cluster-report-v1.schema.json` by
`python scripts/check_report_schema.py`.
