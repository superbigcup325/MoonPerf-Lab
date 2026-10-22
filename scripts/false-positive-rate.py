#!/usr/bin/env python3
"""Measure how much two runs of unchanged code differ, and what that costs.

A regression check compares a subject run against a baseline run of the same
workload, version and host profile. When nothing changed, any flag is a false
positive, so the false-positive rate of a candidate threshold is exactly the
share of run pairs that exceed it.

This script reads a baseline campaign (``scripts/measure-baseline.sh``) and
prints three things per implementation:

* the spread of the median across runs, and the distribution of pairwise
  relative differences (what a threshold has to clear);
* the false-positive rate of several candidate thresholds, including the ones a
  coefficient-of-variation model would pick;
* the spread of the within-run ratio between two implementations, because the
  harness measures them round-robin in one run and that partially cancels the
  host's drift.

Usage:
  scripts/false-positive-rate.py results/tmp/baseline/numeric-scan
  scripts/false-positive-rate.py results/tmp/baseline/* --baseline rust

Only committed-harness artifacts are read; nothing here measures anything.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

THRESHOLDS = (0.01, 0.02, 0.03, 0.05, 0.08, 0.10)


def load_runs(directory: Path) -> list[dict]:
    """Read every artifact under one campaign directory, in run order."""

    artifacts: list[Path] = []
    direct = sorted(directory.glob("*.json"))
    if direct:
        artifacts.extend(direct)
    for run in sorted(directory.glob("run-*")):
        artifacts.extend(sorted(run.glob("*.json")))
    runs = []
    for path in artifacts:
        data = json.loads(path.read_text(encoding="utf-8"))
        if "experiment" not in data:
            continue
        runs.append({"path": path, "artifact": data})
    runs.sort(key=lambda run: (run["artifact"]["experiment"]["started_at"], str(run["path"])))
    return runs


def relative_difference(left: float, right: float) -> float:
    midpoint = (left + right) / 2.0
    return abs(left - right) / midpoint if midpoint else 0.0


def quantile(values: list[float], fraction: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def pct(value: float) -> str:
    return f"{value * 100.0:.2f} %"


def medians_by_implementation(runs: list[dict]) -> dict[str, list[float]]:
    series: dict[str, list[float]] = {}
    for run in runs:
        for implementation in run["artifact"]["implementations"]:
            summary = implementation.get("summary")
            if summary is None:
                continue
            series.setdefault(implementation["id"], []).append(summary["median_ns"])
    return series


def cvs_by_implementation(runs: list[dict]) -> dict[str, list[float]]:
    series: dict[str, list[float]] = {}
    for run in runs:
        for implementation in run["artifact"]["implementations"]:
            summary = implementation.get("summary")
            if summary is None:
                continue
            series.setdefault(implementation["id"], []).append(summary["cv"])
    return series


def ratios_against(runs: list[dict], baseline: str) -> dict[str, list[float]]:
    """Within-run ratio of every other implementation against the baseline."""

    series: dict[str, list[float]] = {}
    for run in runs:
        values = {}
        for implementation in run["artifact"]["implementations"]:
            summary = implementation.get("summary")
            if summary is not None:
                values[implementation["id"]] = summary["median_ns"]
        if baseline not in values:
            continue
        for identifier, median in values.items():
            if identifier == baseline:
                continue
            series.setdefault(identifier, []).append(median / values[baseline])
    return series


def pairwise(values: list[float]) -> list[float]:
    differences = []
    for index, left in enumerate(values):
        for right in values[index + 1 :]:
            differences.append(relative_difference(left, right))
    return differences


def analyse(directory: Path, baseline: str, label: str) -> list[str]:
    runs = load_runs(directory)
    out: list[str] = []
    if not runs:
        return [f"# {label}\n\nNo artifacts under `{directory}`.\n"]

    experiment = runs[0]["artifact"]["experiment"]
    workload = experiment["workload"]
    environment = experiment["environment"]
    cpu = environment["cpu"]
    out.append(f"## {workload['name']} v{workload['version']}")
    out.append("")
    out.append(
        f"{len(runs)} runs, {experiment['dataset']['generator']} "
        f"`count={experiment['dataset']['count']}` "
        f"`sha256={experiment['dataset']['sha256'][:12]}`, "
        f"{cpu['model']} ({cpu['logical_cpus']} CPUs, governor "
        f"`{cpu.get('governor', 'unknown')}`), first run "
        f"`{experiment['started_at']}`, last run "
        f"`{runs[-1]['artifact']['experiment']['started_at']}`."
    )
    out.append("")

    medians = medians_by_implementation(runs)
    cvs = cvs_by_implementation(runs)
    out.append(
        "| Implementation | median of medians (ns) | spread max/min | median CV | "
        + " | ".join(f"FP @ {pct(t)}" for t in THRESHOLDS)
        + " |"
    )
    out.append(
        "| --- | ---: | ---: | ---: | "
        + " | ".join("---:" for _ in THRESHOLDS)
        + " |"
    )
    details: list[str] = []
    for identifier in sorted(medians):
        values = medians[identifier]
        differences = pairwise(values)
        cells = []
        for threshold in THRESHOLDS:
            hits = sum(1 for difference in differences if difference > threshold)
            cells.append(f"{100.0 * hits / len(differences):.1f} %")
        out.append(
            f"| `{identifier}` | {quantile(values, 0.5):.1f} | "
            f"{max(values) / min(values) - 1.0:.2%} | "
            f"{quantile(cvs[identifier], 0.5):.3%} | "
            + " | ".join(cells)
            + " |"
        )
        details.append(
            f"- `{identifier}`: pairwise difference p50 {pct(quantile(differences, 0.5))}, "
            f"p90 {pct(quantile(differences, 0.9))}, "
            f"p95 {pct(quantile(differences, 0.95))}, "
            f"p99 {pct(quantile(differences, 0.99))}; "
            f"1×CV model {pct(math.sqrt(2.0) * quantile(cvs[identifier], 0.5))}, "
            f"2×CV model {pct(2.0 * math.sqrt(2.0) * quantile(cvs[identifier], 0.5))}"
        )
    out.append("")
    out.extend(details)
    out.append("")

    ratios = ratios_against(runs, baseline)
    if ratios:
        out.append(
            f"Within-run ratios against `{baseline}` (the comparison the artifact "
            f"itself reports):"
        )
        out.append("")
        out.append("| Subject vs baseline | median ratio | spread max/min | p50 | p95 |")
        out.append("| --- | ---: | ---: | ---: | ---: |")
        for identifier in sorted(ratios):
            values = ratios[identifier]
            differences = pairwise(values)
            out.append(
                f"| `{identifier}` / `{baseline}` | {quantile(values, 0.5):.4f} | "
                f"{max(values) / min(values) - 1.0:.2%} | "
                f"{pct(quantile(differences, 0.5))} | "
                f"{pct(quantile(differences, 0.95))} |"
            )
        out.append("")
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    parser.add_argument(
        "--baseline",
        default="rust",
        help="implementation used for the within-run ratio (default: rust)",
    )
    args = parser.parse_args(argv)

    lines = [
        "# Baseline noise",
        "",
        "Generated by `scripts/false-positive-rate.py` from baseline campaigns of",
        "the accepted harness. A pair is two runs of unchanged code, so every flag",
        "is a false positive; `FP @ x %` is the share of pairs that would exceed a",
        "threshold of `x %`.",
        "",
    ]
    missing = 0
    for directory in args.directories:
        if not directory.is_dir():
            print(f"not a directory: {directory}", file=sys.stderr)
            missing += 1
            continue
        lines.extend(analyse(directory, args.baseline, directory.name))
    print("\n".join(lines).rstrip() + "\n")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
