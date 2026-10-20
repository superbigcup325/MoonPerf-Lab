"""Command line entry point for the MoonPerf Lab harness."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

from mpf import SCHEMA_VERSION, __version__
from mpf.specs import (
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
            "MoonPerf Lab harness: inspect and validate workloads, "
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
        help="Validate workload manifests, adapters and result artifacts.",
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
        help="validate one result artifact against schemas/result.schema.json",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "list":
            return _list_workloads(args.root)
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

    if not workload_paths and not results:
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

    for raw in results:
        problems = validate_result_file(Path(raw))
        if problems:
            failures += 1
            print(f"FAIL {raw}")
            for problem in problems:
                print(f"     {problem}")
        else:
            print(f"ok   {raw}")

    return 1 if failures else 0


def _as_manifest_path(path: Path) -> Path:
    if path.is_dir():
        return path / "workload.toml"
    return path


if __name__ == "__main__":
    sys.exit(main())
