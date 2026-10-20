"""The runner: correctness gates performance, and artifacts tell the truth."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from mpf.cli import main as cli_main
from mpf.runner import RunError, run_workload
from mpf.specs import validate_result_file

SCRIPT_HEAD = """#!/bin/sh
set -eu
output=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
"""

MANIFEST = """\
schema_version = 1
name = "demo-scan"
version = 1
status = "draft"
tier = "micro"
summary = "runner fixture: one tiny dataset, shell implementations"

[dataset]
generator = "uniform-f64"
count = 16
seed = 1

[dataset.params]
min = -1.0
max = 1.0

[params]
threshold = 0.0

[verify]
mode = "{mode}"
fields = {fields}
reference = "{reference}"
{extra}

[measurement]
warmup = 1
repeats = 2
timeout_s = {timeout_s}
inner_repeats = 1
max_cv = 1.0
"""


def add_implementation(
    workload_dir: Path, impl_id: str, payload: str, *, sleep: str = ""
) -> Path:
    implementation_dir = workload_dir / "implementations" / impl_id
    implementation_dir.mkdir(parents=True)
    (implementation_dir / "adapter.toml").write_text(
        'schema_version = 1\nlanguage = "Shell"\n', encoding="utf-8"
    )
    script = implementation_dir / "run.sh"
    body = f"sleep {sleep}\n" if sleep else ""
    script.write_text(
        SCRIPT_HEAD
        + body
        + "cat > \"$output\" <<'JSON'\n"
        + payload
        + "\nJSON\n",
        encoding="utf-8",
    )
    script.chmod(0o755)
    return implementation_dir


def make_workload(
    root: Path,
    *,
    mode: str = "exact",
    fields: list[str] | None = None,
    extra: str = "",
    timeout_s: float = 10.0,
    reference: str = "alpha",
) -> Path:
    workload_dir = root / "demo-scan"
    workload_dir.mkdir()
    (workload_dir / "workload.toml").write_text(
        MANIFEST.format(
            mode=mode,
            fields=json.dumps(fields or ["n", "count_above"]),
            extra=extra,
            timeout_s=timeout_s,
            reference=reference,
        ),
        encoding="utf-8",
    )
    return workload_dir


class CorrectnessGateTest(unittest.TestCase):
    def test_wrong_output_is_excluded_from_timing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(workload_dir, "beta", '{"n": 15, "count_above": 5}')

            report = run_workload(
                workload_dir, out_dir=root / "out", data_dir=root / ".data"
            )

            self.assertEqual(validate_result_file(report.artifact_path), [])
            implementations = {
                item["id"]: item for item in report.artifact["implementations"]
            }
            self.assertTrue(implementations["alpha"]["correctness"]["ok"])
            self.assertEqual(len(implementations["alpha"]["samples_ns"]), 2)

            beta = implementations["beta"]
            self.assertFalse(beta["correctness"]["ok"])
            self.assertTrue(any("n" in error for error in beta["correctness"]["errors"]))
            self.assertEqual(beta["samples_ns"], [])
            self.assertIsNone(beta["summary"])

            self.assertEqual(report.artifact["verdict"]["status"], "invalid")
            self.assertEqual(report.artifact["comparisons"], [])

            report_text = report.report_path.read_text(encoding="utf-8")
            self.assertIn("invalid", report_text)
            self.assertIn("beta", report_text)
            self.assertIn("No comparison is published", report_text)

    def test_reference_is_verified_before_subjects(self) -> None:
        # Regression: the reference must not be skipped just because a subject
        # sorts before it in discovery order.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root, reference="zeta")
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(workload_dir, "zeta", '{"n": 16, "count_above": 5}')

            report = run_workload(
                workload_dir, out_dir=root / "out", data_dir=root / ".data"
            )

            implementations = {
                item["id"]: item for item in report.artifact["implementations"]
            }
            self.assertTrue(implementations["zeta"]["correctness"]["ok"])
            self.assertTrue(implementations["alpha"]["correctness"]["ok"])
            self.assertEqual(report.artifact["verdict"]["status"], "ok")

    def test_tolerance_accepts_a_rounding_difference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(
                root, mode="tolerance", fields=["sum", "n"], extra="rtol = 1.0e-6"
            )
            add_implementation(workload_dir, "alpha", '{"sum": 1.0, "n": 16}')
            add_implementation(workload_dir, "beta", '{"sum": 1.0000001, "n": 16}')

            report = run_workload(
                workload_dir, out_dir=root / "out", data_dir=root / ".data"
            )

            implementations = {
                item["id"]: item for item in report.artifact["implementations"]
            }
            self.assertTrue(implementations["beta"]["correctness"]["ok"])
            self.assertEqual(report.artifact["verdict"]["status"], "ok")
            self.assertEqual(len(report.artifact["comparisons"]), 1)
            comparison = report.artifact["comparisons"][0]
            self.assertEqual(comparison["baseline"], "alpha")
            self.assertEqual(comparison["subject"], "beta")

    def test_float_field_emitted_as_integer_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(
                root, mode="tolerance", fields=["sum", "n"], extra="rtol = 1.0e-6"
            )
            add_implementation(workload_dir, "alpha", '{"sum": 1.0, "n": 16}')
            add_implementation(workload_dir, "beta", '{"sum": 1, "n": 16}')

            report = run_workload(
                workload_dir, out_dir=root / "out", data_dir=root / ".data"
            )

            beta = next(
                item
                for item in report.artifact["implementations"]
                if item["id"] == "beta"
            )
            self.assertFalse(beta["correctness"]["ok"])
            self.assertEqual(beta["samples_ns"], [])
            self.assertEqual(report.artifact["verdict"]["status"], "invalid")

    def test_timeout_is_a_failure_without_samples(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root, timeout_s=0.2)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(
                workload_dir, "beta", '{"n": 16, "count_above": 5}', sleep="2"
            )

            report = run_workload(
                workload_dir, out_dir=root / "out", data_dir=root / ".data"
            )

            beta = next(
                item
                for item in report.artifact["implementations"]
                if item["id"] == "beta"
            )
            self.assertFalse(beta["correctness"]["ok"])
            self.assertTrue(any("timed out" in error for error in beta["correctness"]["errors"]))
            self.assertEqual(beta["samples_ns"], [])
            self.assertEqual(report.artifact["verdict"]["status"], "invalid")

    def test_measurement_failure_produces_no_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            out_dir = root / "out"
            _make_measured_invocation_fail(workload_dir)
            with self.assertRaises(RunError):
                run_workload(
                    workload_dir, out_dir=out_dir, data_dir=root / ".data"
                )
            self.assertFalse((out_dir / "demo-scan").exists())


def _make_measured_invocation_fail(workload_dir: Path) -> None:
    """Make the measured invocation fail after correctness passed.

    The adapter script succeeds on its first invocation (the correctness run)
    and fails afterwards, which only the measurement performs.
    """

    implementation_dir = workload_dir / "implementations" / "alpha"
    script = implementation_dir / "run.sh"
    script.write_text(
        SCRIPT_HEAD
        + 'count_file="$(dirname "$output")/runs.txt"\n'
        + 'if [ -f "$count_file" ]; then echo "boom" >&2; exit 3; fi\n'
        + 'echo 1 > "$count_file"\n'
        + 'cat > "$output" <<\'JSON\'\n{"n": 16, "count_above": 5}\nJSON\n',
        encoding="utf-8",
    )
    script.chmod(0o755)


class RunnerPathTest(unittest.TestCase):
    def test_relative_workload_path_is_supported(self) -> None:
        # Regression: the documented invocation passes a path relative to the
        # repository root. Implementation directories must be resolved before
        # they are used as subprocess paths.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(workload_dir, "beta", '{"n": 16, "count_above": 5}')

            previous = Path.cwd()
            os.chdir(root)
            try:
                report = run_workload(
                    Path("demo-scan"),
                    out_dir=root / "out",
                    data_dir=root / ".data",
                )
            finally:
                os.chdir(previous)

            self.assertEqual(report.artifact["verdict"]["status"], "ok")
            self.assertTrue(report.artifact_path.is_file())
            self.assertTrue(report.report_path.is_file())


class CliTest(unittest.TestCase):
    def test_run_and_report_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(workload_dir, "beta", '{"n": 16, "count_above": 5}')
            out_dir = root / "out"

            code = cli_main(["run", str(workload_dir), "--out", str(out_dir)])
            self.assertEqual(code, 0)

            artifacts = sorted(out_dir.glob("*.json"))
            self.assertEqual(len(artifacts), 1)
            self.assertTrue(artifacts[0].with_suffix(".md").is_file())

            code = cli_main(["report", str(artifacts[0])])
            self.assertEqual(code, 0)
            text = artifacts[0].with_suffix(".md").read_text(encoding="utf-8")
            self.assertIn("## Measurement", text)
            self.assertIn("## Verdict", text)
            self.assertIn("mpf run", text)

    def test_invalid_run_exits_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = make_workload(root)
            add_implementation(workload_dir, "alpha", '{"n": 16, "count_above": 5}')
            add_implementation(workload_dir, "beta", '{"n": 1, "count_above": 5}')

            code = cli_main(["run", str(workload_dir), "--out", str(root / "out")])
            self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
