#!/usr/bin/env python3
"""Cross-check implementations against a workload's reference output.

Runs one adapter invocation per implementation on the same dataset and applies
the workload's own verification rule. CI uses it so an adapter that drifts from
the reference fails without publishing a performance number.

Usage:
    python scripts/crosscheck-workload.py numeric-scan --subject c
    python scripts/crosscheck-workload.py hash-join --dataset .data/hash-join.bin \
        --sha256 a413e1de... --subject moonbit --subject c

The dataset is generated with the Python oracle when the workload's generator is
one the oracle implements (`uniform-f64`); for every other generator pass
`--dataset`, and `--sha256` to pin its identity.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from mpf.dataset import ensure_dataset, render_params  # noqa: E402
from mpf.runner import compare_values, read_output  # noqa: E402
from mpf.specs import Workload, load_workload  # noqa: E402


def resolve_manifest(argument: str) -> Path:
    candidate = Path(argument)
    if candidate.suffix == ".toml":
        return candidate if candidate.is_absolute() else Path.cwd() / candidate
    return ROOT / "workloads" / argument / "workload.toml"


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


def resolve_dataset(workload: Workload, arguments: argparse.Namespace) -> Path:
    if arguments.dataset:
        dataset = Path(arguments.dataset).resolve()
        if not dataset.is_file():
            raise SystemExit(f"no dataset at {dataset}")
        if arguments.sha256:
            digest = hashlib.sha256(dataset.read_bytes()).hexdigest()
            if digest != arguments.sha256:
                raise SystemExit(
                    f"dataset SHA-256 is {digest}, not {arguments.sha256}"
                )
        else:
            print(f"note: {dataset.name} identity is not pinned (no --sha256)")
        return dataset

    record = ensure_dataset(workload)
    if arguments.sha256 and record.sha256 != arguments.sha256:
        raise SystemExit(f"dataset SHA-256 is {record.sha256}, not {arguments.sha256}")
    return record.path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workload", help="workload name, or a path to its manifest")
    parser.add_argument(
        "--dataset", help="dataset file; generated with the oracle when omitted"
    )
    parser.add_argument("--sha256", help="expected dataset SHA-256")
    parser.add_argument(
        "--subject",
        action="append",
        default=[],
        help="implementation id to check (repeatable); default: every non-reference id",
    )
    parser.add_argument("--repeat", type=int, default=3)
    arguments = parser.parse_args()

    workload = load_workload(resolve_manifest(arguments.workload))
    verify = workload.data["verify"]
    reference_id = str(verify["reference"])
    ids = {item.id for item in workload.implementations}
    subjects = arguments.subject or sorted(ids - {reference_id})
    if not subjects:
        raise SystemExit(f"{workload.name}: nothing to check against {reference_id}")
    for subject_id in subjects:
        if subject_id not in ids:
            raise SystemExit(f"{workload.name}: no '{subject_id}' implementation")

    dataset = resolve_dataset(workload, arguments)

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        params = root / "params.txt"
        params.write_text(
            render_params(workload.data.get("params", {})), encoding="utf-8"
        )
        reference = run_adapter(
            workload,
            reference_id,
            dataset,
            params,
            root / "reference.json",
            arguments.repeat,
        )
        results = {
            subject_id: run_adapter(
                workload,
                subject_id,
                dataset,
                params,
                root / f"{subject_id}.json",
                arguments.repeat,
            )
            for subject_id in subjects
        }

    failures = 0
    for subject_id, values in results.items():
        errors = compare_values(
            values,
            reference,
            verify["fields"],
            str(verify["mode"]),
            float(verify.get("rtol", 0.0)),
            float(verify.get("atol", 0.0)),
        )
        if errors:
            failures += 1
            for error in errors:
                print(f"{subject_id}: {error}", file=sys.stderr)
        else:
            print(
                f"crosscheck ok: {subject_id} matches {reference_id} on "
                f"{len(verify['fields'])} fields (repeat={arguments.repeat})"
            )
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
