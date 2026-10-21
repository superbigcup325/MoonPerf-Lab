#!/usr/bin/env python3
"""Correctness cross-check: the C adapter against the Rust reference.

The C reference exists to add an independent compiler to the micro comparison.
This script runs one invocation per adapter on the harness dataset and applies
the workload's own verification rule, so a drift in either adapter fails CI
without publishing a performance number.

Usage: python scripts/crosscheck-numeric-scan.py [--repeat K]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mpf.dataset import ensure_dataset, render_params  # noqa: E402
from mpf.runner import compare_values, read_output  # noqa: E402
from mpf.specs import Workload, load_workload  # noqa: E402

MANIFEST = Path(__file__).resolve().parent.parent / "workloads" / "numeric-scan" / "workload.toml"


def run_adapter(
    workload: Workload,
    implementation_id: str,
    dataset: Path,
    params: Path,
    output: Path,
    repeat: int,
) -> dict[str, object]:
    implementation = {item.id: item for item in workload.implementations}.get(
        implementation_id
    )
    if implementation is None:
        raise SystemExit(f"{workload.name}: no '{implementation_id}' implementation")
    run_script = implementation.directory / "run.sh"
    if not run_script.is_file():
        raise SystemExit(f"{implementation_id}: missing {run_script}")
    command = [
        str(run_script),
        "--input",
        str(dataset),
        "--params",
        str(params),
        "--output",
        str(output),
        "--repeat",
        str(repeat),
    ]
    result = subprocess.run(
        command, cwd=implementation.directory, capture_output=True, text=True
    )
    if result.returncode != 0:
        raise SystemExit(
            f"{implementation_id}: adapter exited {result.returncode}\n"
            f"{result.stdout}{result.stderr}"
        )
    fields = workload.data["verify"]["fields"]
    values, errors = read_output(output, fields)
    if errors:
        raise SystemExit(f"{implementation_id}: {'; '.join(errors)}")
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeat", type=int, default=3)
    arguments = parser.parse_args()

    workload = load_workload(MANIFEST)
    dataset = ensure_dataset(workload)
    verify = workload.data["verify"]
    reference_id = str(verify["reference"])
    subject_id = "c"
    if subject_id not in {item.id for item in workload.implementations}:
        raise SystemExit(f"{workload.name}: no '{subject_id}' implementation")

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        params = root / "params.txt"
        params.write_text(render_params(workload.data["params"]), encoding="utf-8")
        reference = run_adapter(
            workload, reference_id, dataset.path, params, root / "reference.json", arguments.repeat
        )
        subject = run_adapter(
            workload, subject_id, dataset.path, params, root / "subject.json", arguments.repeat
        )

    errors = compare_values(
        subject,
        reference,
        verify["fields"],
        str(verify["mode"]),
        float(verify.get("rtol", 0.0)),
        float(verify.get("atol", 0.0)),
    )
    if errors:
        for error in errors:
            print(f"{subject_id}: {error}", file=sys.stderr)
        return 1
    print(
        f"crosscheck ok: {subject_id} matches {reference_id} on "
        f"{len(verify['fields'])} fields (repeat={arguments.repeat})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
