"""Render the Markdown view of a result artifact.

The JSON artifact is the source of truth; this module never measures anything
and never edits numbers. Running it twice on the same artifact produces the
same report.
"""

from __future__ import annotations

from typing import Any, Sequence

from mpf.specs import Workload


def research_question(workload: Workload) -> str:
    """The workload README's research question, or the manifest summary."""

    readme = workload.directory / "README.md"
    if readme.is_file():
        section = _markdown_section(readme.read_text(encoding="utf-8"), "Research question")
        if section:
            return section
    return str(workload.data.get("summary", ""))


def _markdown_section(text: str, title: str) -> str:
    lines = text.splitlines()
    collected: list[str] = []
    active = False
    for line in lines:
        if line.strip() == f"## {title}":
            active = True
            continue
        if active and line.startswith("## "):
            break
        if active:
            collected.append(line)
    return " ".join(part.strip() for part in collected if part.strip())


def _ns(value: float | int | None) -> str:
    if value is None:
        return "-"
    return f"{value:,.0f}"


def _pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:+.2f} %"


def _ratio(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.3f}"


def render_report(artifact: dict[str, Any], question: str) -> str:
    experiment = artifact["experiment"]
    workload = experiment["workload"]
    environment = experiment["environment"]
    measurement = experiment["measurement"]
    dataset = experiment["dataset"]
    implementations: Sequence[dict[str, Any]] = artifact["implementations"]
    comparisons: Sequence[dict[str, Any]] = artifact.get("comparisons", [])
    verdict = artifact["verdict"]

    title = f"{workload['name']} v{workload['version']}"
    lines: list[str] = [
        f"# {title}",
        "",
        "**Generated report — do not edit by hand.** It is rendered from the "
        f"JSON artifact `{experiment['id']}.json`; the JSON is the source of truth.",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Workload | `{workload['name']}` v{workload['version']} |",
        f"| Tier | `{workload['tier']}` |",
        f"| Verdict | **{verdict['status']}** |",
        f"| Experiment | `{experiment['id']}` |",
        f"| Started (UTC) | {experiment['started_at']} |",
        f"| Finished (UTC) | {experiment.get('finished_at', '-')} |",
        "",
        "## Research question",
        "",
        question.strip() or "_The workload does not declare a research question._",
        "",
        "## Environment",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| OS | {environment['os']} {environment.get('os_release', '')} |".rstrip(),
        f"| Architecture | {environment['arch']} |",
        f"| CPU | {environment['cpu']['model']} ({environment['cpu']['logical_cpus']} logical CPUs) |",
        f"| CPU governor | {environment['cpu'].get('governor') or 'not recorded'} |",
        f"| Memory | {environment['memory_bytes'] / 1024**3:.1f} GiB |",
        f"| Harness | mpf {experiment['harness']['version']} on Python {experiment['harness']['python']} |",
        f"| Source | commit `{experiment['source']['commit'] or 'unknown'}`"
        f"{' (dirty)' if experiment['source']['dirty'] else ''}"
        f" on `{experiment['source']['branch'] or 'unknown'}` |",
        "",
        "## Dataset",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Generator | `{dataset['generator']}` |",
        f"| Count | {dataset['count']:,} elements ({dataset['bytes']:,} bytes) |",
        f"| Seed | {dataset['seed']} |",
        f"| Params | {_params(dataset.get('params', {}))} |",
        f"| SHA-256 | `{dataset['sha256']}` |",
        "",
        "## Correctness gate",
        "",
        "| Implementation | Language | Passed | Checked against | Notes |",
        "| --- | --- | --- | --- | --- |",
    ]

    for implementation in implementations:
        correctness = implementation["correctness"]
        notes = "; ".join(correctness["errors"]) if correctness["errors"] else "ok"
        lines.append(
            f"| `{implementation['id']}` | {implementation['language']} "
            f"| {'yes' if correctness['ok'] else '**no**'} "
            f"| {correctness.get('checked_against') or 'reference'} "
            f"| {notes} |"
        )

    lines.extend(
        [
            "",
            "Only implementations that passed this gate are timed.",
            "",
            "## Measurement",
            "",
            f"Warmup: {measurement['warmup']} invocations per implementation · "
            f"Repeats: {measurement['repeats']} rounds · "
            f"Inner repeats: {measurement['inner_repeats']} · "
            f"Timeout: {measurement['timeout_s']} s · "
            f"Order: {measurement['order']} · Clock: {measurement['clock']}.",
            "",
            f"All times are per-iteration nanoseconds for `{workload['name']}` "
            f"v{workload['version']} ({workload['tier']}), measured on the host above.",
            "",
            "| Implementation | Samples | Median | Mean | Min | Stddev | CV |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    by_id = {implementation["id"]: implementation for implementation in implementations}
    for implementation in implementations:
        summary = implementation.get("summary")
        if summary is None:
            lines.append(
                f"| `{implementation['id']}` | - | - | - | - | - | - |"
            )
            continue
        lines.append(
            f"| `{implementation['id']}` | {summary['count']} "
            f"| {_ns(summary['median_ns'])} | {_ns(summary['mean_ns'])} "
            f"| {_ns(summary['min_ns'])} | {_ns(summary['stdev_ns'])} "
            f"| {summary['cv'] * 100:.2f} % |"
        )

    if comparisons:
        lines.extend(
            [
                "",
                "## Comparison",
                "",
                "Ratio is subject median divided by baseline median; below 1 means "
                "the subject is faster. This is one workload on one host, not a "
                "language ranking.",
                "",
                "| Subject | Baseline | Subject median (ns) | Baseline median (ns) | Ratio | Delta |",
                "| --- | --- | ---: | ---: | ---: | ---: |",
            ]
        )
        for comparison in comparisons:
            lines.append(
                f"| `{comparison['subject']}` | `{comparison['baseline']}` "
                f"| {_ns(comparison['subject_ns'])} "
                f"| {_ns(comparison['baseline_ns'])} "
                f"| {_ratio(comparison['ratio'])} "
                f"| {_pct(comparison['delta_pct'])} |"
            )
    else:
        lines.extend(
            [
                "",
                "## Comparison",
                "",
                "No comparison is published for this artifact: the verdict is "
                f"`{verdict['status']}`, so the numbers are not used for a claim.",
            ]
        )

    lines.extend(["", "## Raw samples", "", "Per-iteration nanoseconds, in measurement order."])
    for implementation in implementations:
        samples = implementation["samples_ns"]
        if not samples:
            continue
        lines.extend(
            [
                "",
                f"`{implementation['id']}` ({len(samples)} samples):",
                "",
                "```text",
                " ".join(str(sample) for sample in samples),
                "```",
            ]
        )

    lines.extend(
        [
            "",
            "## Verdict",
            "",
            f"**{verdict['status']}**",
        ]
    )
    if verdict["notes"]:
        lines.extend(["", *[f"- {note}" for note in verdict["notes"]]])
    else:
        lines.extend(["", "The correctness gate passed and every sample set is stable."])

    lines.extend(
        [
            "",
            "## Reproduce",
            "",
            "```bash",
            experiment["reproduce_command"],
            "```",
            "",
            "Same-host acceptance: identical correctness verdict and medians within "
            "±5 % of this artifact. Cross-machine numbers are directional only.",
            "",
            f"_Artifact: `{experiment['id']}.json` · generated by `mpf report`._",
            "",
        ]
    )
    return "\n".join(lines)


def _params(params: dict[str, Any]) -> str:
    if not params:
        return "none"
    return ", ".join(f"`{key}={params[key]}`" for key in sorted(params))
