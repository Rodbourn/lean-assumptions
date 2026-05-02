# schema

Current public schemas:

- `report-v1.schema.json`: single-report JSON emitted by `LeanAssumptions.Render.renderJsonString`
- `batch-report-v1.schema.json`: batch JSON emitted by `LeanAssumptions.Render.renderBatchJsonString` and the CLI
- `delta-report-v1.schema.json`: delta JSON emitted by `LeanAssumptions.Delta.renderJsonString` and CLI `--diff`
- `cluster-report-v1.schema.json`: failure-cluster JSON emitted by `LeanAssumptions.Cluster.renderJsonString` and CLI `--cluster`
- `policy-v1.schema.json`: versioned policy files accepted by the CLI

Schema validation commands:

```text
python scripts/check_report_schema.py
python scripts/check_policy_schema.py
```

The local validators intentionally use only Python standard-library facilities
so schema checks do not add runtime or CI network dependencies.
