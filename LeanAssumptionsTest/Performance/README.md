# Performance

Phase 4 tracks a smoke-level performance baseline in `baseline.json`.

The baseline is intentionally conservative:

- cases exercise the public CLI against representative fixture declarations
- each case must exit successfully, emit valid JSON, and scan exactly the
  expected declarations
- timing thresholds are broad because hosted-runner timing is not a correctness
  signal
- the benchmark does not justify weakening classification, hiding unknowns, or
  treating performance as proof of semantic correctness

Run the validator with:

```text
python scripts/check_performance_baseline.py
```
