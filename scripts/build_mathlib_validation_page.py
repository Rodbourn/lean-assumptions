"""Build the published mathlib-scale validation page from scan artifacts.

Reads batch JSON artifacts produced by `lake exe lean-assumptions
--scan-module <module> --format json` plus a workflow-written metadata file,
and emits a static site directory containing `summary.json` (machine-readable,
used by the workflow's skip logic) and `index.html`.

The page publishes AGGREGATES ONLY: per-module counts, totals, unknown rates,
determinism, and timings. It never copies declaration names or per-declaration
findings out of the artifacts. These runs measure classifier behavior at
scale — conservatism, determinism, and performance — not the audited corpus:
strict-policy failures on real mathematical code are expected and are not a
judgment of that code.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def load_artifact(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    summary = data.get("summary")
    if not isinstance(summary, dict):
        raise ValueError(f"{path}: artifact has no summary block")
    return data


def module_row(module: str, data: dict[str, Any], seconds: float | None) -> dict[str, Any]:
    summary = data["summary"]
    return {
        "module": module,
        "declarations_scanned": summary["declarations_scanned"],
        "declarations_passed": summary["declarations_passed"],
        "declarations_warned": summary["declarations_warned"],
        "declarations_failed": summary["declarations_failed"],
        "declarations_with_unknown_nodes": summary["declarations_with_unknown_nodes"],
        "wall_seconds": seconds,
    }


def build_summary(meta: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    scanned = sum(r["declarations_scanned"] for r in rows)
    unknown = sum(r["declarations_with_unknown_nodes"] for r in rows)
    return {
        "page_kind": "lean-assumptions mathlib-scale validation (aggregates only)",
        "mathlib_tag": meta["mathlib_tag"],
        "mathlib_toolchain": meta["mathlib_toolchain"],
        "tool_rev": meta["tool_rev"],
        "tool_version": meta["tool_version"],
        "run_date": meta["run_date"],
        "determinism_byte_identical_rescan": meta["determinism_byte_identical_rescan"],
        "modules": rows,
        "totals": {
            "declarations_scanned": scanned,
            "declarations_passed": sum(r["declarations_passed"] for r in rows),
            "declarations_warned": sum(r["declarations_warned"] for r in rows),
            "declarations_failed": sum(r["declarations_failed"] for r in rows),
            "declarations_with_unknown_nodes": unknown,
            "unknown_rate": round(unknown / scanned, 4) if scanned else None,
        },
        "limitations": [
            "aggregates of classifier behavior only; no per-declaration findings are published",
            "strict-policy failures on real mathematical code are expected and are not a judgment of the audited corpus",
            "audits elaborated declaration types only; does not validate proof axioms, sandbox execution, or prove theorem-statement equivalence",
            "counts are environment constants attributed to each module, including auto-generated auxiliaries",
        ],
    }


def render_page(summary: dict[str, Any]) -> str:
    def esc(value: Any) -> str:
        return html.escape(str(value))

    rows = "\n".join(
        "<tr><td>{m}</td><td>{s}</td><td>{p}</td><td>{w}</td><td>{f}</td><td>{u}</td><td>{t}</td></tr>".format(
            m=esc(r["module"]),
            s=esc(r["declarations_scanned"]),
            p=esc(r["declarations_passed"]),
            w=esc(r["declarations_warned"]),
            f=esc(r["declarations_failed"]),
            u=esc(r["declarations_with_unknown_nodes"]),
            t=esc(f"{r['wall_seconds']:.0f}s" if r["wall_seconds"] is not None else "n/a"),
        )
        for r in summary["modules"]
    )
    totals = summary["totals"]
    unknown_rate = totals["unknown_rate"]
    unknown_pct = f"{unknown_rate * 100:.2f}%" if unknown_rate is not None else "n/a"
    determinism = (
        "byte-identical artifact on rescan"
        if summary["determinism_byte_identical_rescan"]
        else "RESCAN DIFFERED — determinism regression"
    )
    limitations = "\n".join(f"<li>{esc(line)}</li>" for line in summary["limitations"])
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>lean-assumptions — mathlib-scale validation</title>
<style>
body {{ font-family: system-ui, sans-serif; max-width: 52rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #999; padding: 0.3rem 0.6rem; text-align: right; }}
th:first-child, td:first-child {{ text-align: left; }}
code {{ background: #eee; padding: 0 0.2rem; }}
@media (prefers-color-scheme: dark) {{
body {{ background: #111; color: #ddd; }}
th, td {{ border-color: #555; }}
code {{ background: #333; }}
}}
</style>
</head>
<body>
<h1>lean-assumptions — mathlib-scale validation</h1>
<p>This page records how the
<a href="https://github.com/Rodbourn/lean-assumptions">lean-assumptions</a>
classifier behaves when scanning real mathematical code at scale. It measures
the <em>tool</em> — conservatism, determinism, and performance — not the
audited corpus: strict-policy failures on mathlib are expected (real theorems
legitimately take typeclass and proposition binders) and are not a judgment of
mathlib. Only aggregates are published. Methodology:
<a href="https://github.com/Rodbourn/lean-assumptions/blob/main/docs/mathlib-scale-validation.md">docs/mathlib-scale-validation.md</a>.</p>
<ul>
<li>mathlib release: <code>{esc(summary["mathlib_tag"])}</code>
(toolchain <code>{esc(summary["mathlib_toolchain"])}</code>)</li>
<li>tool: version <code>{esc(summary["tool_version"])}</code>,
revision <code>{esc(summary["tool_rev"])}</code></li>
<li>run date: {esc(summary["run_date"])}</li>
<li>determinism: {esc(determinism)}</li>
</ul>
<table>
<tr><th>Module</th><th>Scanned</th><th>Passed</th><th>Warned</th><th>Failed</th><th>Unknown-bearing</th><th>Wall</th></tr>
{rows}
<tr><th>Total</th><th>{esc(totals["declarations_scanned"])}</th><th>{esc(totals["declarations_passed"])}</th><th>{esc(totals["declarations_warned"])}</th><th>{esc(totals["declarations_failed"])}</th><th>{esc(totals["declarations_with_unknown_nodes"])}</th><th></th></tr>
</table>
<p>Unknown-bearing rate: <strong>{esc(unknown_pct)}</strong> of scanned
declarations carry at least one conservatively reported <code>unknown</code>
node (the polarity invariant resolving unrecognized shapes to
<code>unknown</code> rather than optimistically to <code>pure_data</code>).</p>
<h2>What this page does not claim</h2>
<ul>
{limitations}
</ul>
<p><a href="summary.json">summary.json</a> carries the same data
machine-readably.</p>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True, type=Path,
                        help="directory of <Module>.json batch artifacts")
    parser.add_argument("--meta", required=True, type=Path,
                        help="metadata JSON written by the workflow")
    parser.add_argument("--out", required=True, type=Path,
                        help="output site directory")
    args = parser.parse_args()

    meta = json.loads(args.meta.read_text(encoding="utf-8"))
    timings = meta.get("wall_seconds", {})
    rows = []
    for path in sorted(args.artifacts.glob("*.json")):
        module = path.stem
        rows.append(module_row(module, load_artifact(path), timings.get(module)))
    if not rows:
        raise SystemExit("no scan artifacts found")

    summary = build_summary(meta, rows)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "summary.json").write_text(
        json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    (args.out / "index.html").write_text(render_page(summary), encoding="utf-8")
    print(f"validation page built: {args.out}/index.html "
          f"({summary['totals']['declarations_scanned']} declarations aggregated)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
