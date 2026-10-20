"""Command line entry point for the MoonPerf Lab harness."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from mpf import SCHEMA_VERSION, __version__
from mpf.report import render_report, research_question
from mpf.runner import RunError, run_workload
from mpf.specs import (
    REPO_ROOT,
    WORKLOADS_DIR,
    SpecError,
    discover_workload_paths,
    load_workload,
    validate_result_file,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mpf",
        description=(
            "MoonPerf Lab harness: run, inspect and validate workloads, "
            "implementations and experiment artifacts."
        ),
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"mpf {__version__} (schema v{SCHEMA_VERSION})",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    lister = subcommands.add_parser(
        "list", help="List workloads and the implementations discovered on disk."
    )
    lister.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=WORKLOADS_DIR,
        help="workloads root directory (default: workloads/)",
    )

    validator = subcommands.add_parser(
        "validate",
        help="Validate workload manifests, adapters, results and schemas.",
    )
    validator.add_argument(
        "paths",
        nargs="*",
        metavar="PATH",
        help=(
            "workload directories or workload.toml files "
            "(default: every workload under workloads/)"
        ),
    )
    validator.add_argument(
        "--result",
        action="append",
        default=[],
        metavar="FILE",
        help=(
            "validate one result artifact against schemas/result.schema.json "
            "(default: every committed artifact under results/)"
        ),
    )

    runner = subcommands.add_parser(
        "run",
        help="Build, verify and measure one workload, then record the artifact.",
    )
    runner.add_argument(
        "workload",
        metavar="WORKLOAD",
        help="workload directory or workload.toml file",
    )
    runner.add_argument(
        "--out",
        type=Path,
        default=None,
        metavar="DIR",
        help="artifact directory (default: results/<workload>)",
    )

    reporter = subcommands.add_parser(
        "report",
        help="Regenerate the Markdown report from a committed result artifact.",
    )
    reporter.add_argument("artifact", metavar="ARTIFACT", help="result JSON file")
    reporter.add_argument(
        "--workload",
        type=Path,
        default=None,
        metavar="DIR",
        help="workload directory supplying the research question "
        "(default: workloads/<name> from the artifact)",
    )
    reporter.add_argument(
        "--out",
        type=Path,
        default=None,
        metavar="FILE",
        help="report path (default: alongside the artifact)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "list":
            return _list_workloads(args.root)
        if args.command == "run":
            return _run(args.workload, args.out)
        if args.command == "report":
            return _report(args.artifact, args.workload, args.out)
        return _validate(args.paths, args.result)
    except SpecError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def _list_workloads(root: Path) -> int:
    paths = discover_workload_paths(root)
    if not paths:
        print(f"no workload manifests under {root}", file=sys.stderr)
        return 1

    rows: list[tuple[str, str, str, str, str]] = []
    for path in paths:
        try:
            workload = load_workload(path)
        except SpecError as exc:
            rows.append(("<invalid>", "-", "-", "-", str(exc).splitlines()[0]))
            continue
        implementations = ", ".join(
            implementation.id for implementation in workload.implementations
        )
        rows.append(
            (
                workload.name,
                str(workload.version),
                workload.tier,
                workload.status,
                implementations or "-",
            )
        )

    headers = ("WORKLOAD", "VERSION", "TIER", "STATUS", "IMPLEMENTATIONS")
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in rows))
        for index in range(len(headers))
    ]
    print("  ".join(header.ljust(width) for header, width in zip(headers, widths)))
    for row in rows:
        print("  ".join(cell.ljust(width) for cell, width in zip(row, widths)))
    return 0


def _validate(raw_paths: Sequence[str], results: Sequence[str]) -> int:
    failures = 0
    if raw_paths:
        workload_paths = [_as_manifest_path(Path(raw)) for raw in raw_paths]
    else:
        workload_paths = discover_workload_paths()

    if results:
        result_paths = [Path(raw) for raw in results]
    else:
        result_paths = _committed_results()

    if not workload_paths and not result_paths:
        print("nothing to validate", file=sys.stderr)
        return 1

    for path in workload_paths:
        try:
            workload = load_workload(path)
        except SpecError as exc:
            failures += 1
            print(f"FAIL {path}")
            for line in str(exc).splitlines():
                print(f"     {line.strip()}")
            continue
        implementations = ", ".join(
            implementation.id for implementation in workload.implementations
        )
        print(
            f"ok   {workload.name} v{workload.version} "
            f"({workload.status}, {workload.tier}, "
            f"implementations: {implementations or 'none'})"
        )

    for path in result_paths:
        problems = validate_result_file(path)
        if problems:
            failures += 1
            print(f"FAIL {path}")
            for problem in problems:
                print(f"     {problem}")
        else:
            print(f"ok   {path}")

    return 1 if failures else 0


def _run(raw_workload: str, out: Path | None) -> int:
    report = run_workload(Path(raw_workload), out_dir=out)
    artifact = report.artifact
    experiment = artifact["experiment"]

    for implementation in artifact["implementations"]:
        summary = implementation.get("summary")
        if summary is None:
            state = "excluded" if not implementation["correctness"]["ok"] else "no samples"
            print(f"  {implementation['id']:<10} {state}")
            continue
        print(
            f"  {implementation['id']:<10} median {summary['median_ns']:>12,.0f} ns/iter "
            f"cv {summary['cv'] * 100:.2f} %"
        )

    verdict = artifact["verdict"]
    print(
        f"verdict {verdict['status']}  "
        f"({experiment['workload']['name']} v{experiment['workload']['version']}, "
        f"{experiment['id']})"
    )
    for note in verdict["notes"]:
        print(f"  note: {note}")
    print(f"artifact {report.artifact_path}")
    print(f"report   {report.report_path}")
    return 0 if verdict["status"] != "invalid" else 1


def _report(raw_artifact: str, workload_dir: Path | None, out: Path | None) -> int:
    artifact_path = Path(raw_artifact)
    try:
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SpecError(f"{artifact_path}: invalid JSON: {exc}") from exc
    except OSError as exc:
        raise SpecError(f"{artifact_path}: {exc.strerror}") from exc

    name = artifact["experiment"]["workload"]["name"]
    directory = workload_dir if workload_dir is not None else REPO_ROOT / "workloads" / name
    try:
        workload = load_workload(directory)
        question = research_question(workload)
    except SpecError:
        question = ""

    destination = out if out is not None else artifact_path.with_suffix(".md")
    destination.write_text(render_report(artifact, question), encoding="utf-8")
    print(f"wrote {destination}")
    return 0


def _committed_results() -> list[Path]:
    results_dir = REPO_ROOT / "results"
    if not results_dir.is_dir():
        return []
    return sorted(
        path
        for path in results_dir.rglob("*.json")
        if "tmp" not in path.parts
    )


def _as_manifest_path(path: Path) -> Path:
    if path.is_dir():
        return path / "workload.toml"
    return path


if __name__ == "__main__":
    sys.exit(main())
