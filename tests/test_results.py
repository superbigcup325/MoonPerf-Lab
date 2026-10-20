"""Result artifact tests: the schema must accept real shapes and reject drift."""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from mpf.specs import validate_instance, validate_result_file


def valid_result() -> dict:
    return {
        "schema_version": 1,
        "experiment": {
            "id": "2026-10-20T000000Z-numeric-scan",
            "started_at": "2026-10-20T00:00:00Z",
            "finished_at": "2026-10-20T00:01:30Z",
            "harness": {"version": "0.1.0", "python": "3.12.0"},
            "source": {"commit": "0" * 40, "dirty": False, "branch": "main"},
            "workload": {
                "name": "numeric-scan",
                "version": 1,
                "tier": "micro",
                "manifest_sha256": "a" * 64,
            },
            "dataset": {
                "generator": "uniform-f64",
                "count": 1000,
                "seed": 1,
                "sha256": "b" * 64,
                "bytes": 8000,
            },
            "params": {"threshold": 0.0},
            "measurement": {
                "warmup": 3,
                "repeats": 10,
                "timeout_s": 120,
                "inner_repeats": 10,
                "max_cv": 0.05,
                "order": "round-robin",
                "clock": "monotonic",
            },
            "environment": {
                "os": "Linux",
                "os_release": "6.8.0-45-generic",
                "arch": "x86_64",
                "cpu": {
                    "model": "Example CPU",
                    "logical_cpus": 8,
                    "governor": "performance",
                },
                "memory_bytes": 16 * 1024**3,
            },
            "reproduce_command": "mpf run workloads/numeric-scan",
        },
        "implementations": [
            {
                "id": "rust",
                "language": "Rust",
                "reference": True,
                "toolchain": "rustc 1.99.0",
                "build": {
                    "ok": True,
                    "skipped": False,
                    "command": "cargo build --release",
                    "duration_ms": 1200.0,
                    "log_sha256": "c" * 64,
                    "log_tail": "",
                },
                "correctness": {
                    "ok": True,
                    "mode": "tolerance",
                    "checked_against": None,
                    "output_sha256": "d" * 64,
                    "values": {"n": 1000, "sum": 1.5},
                    "errors": [],
                },
                "samples_ns": [3_000_000, 3_100_000, 2_950_000],
                "summary": {
                    "count": 3,
                    "min_ns": 2_950_000,
                    "median_ns": 3_000_000.0,
                    "mean_ns": 3_016_666.67,
                    "stdev_ns": 76_376.0,
                    "cv": 0.0253,
                },
            }
        ],
        "comparisons": [
            {
                "baseline": "rust",
                "subject": "moonbit",
                "metric": "median_ns",
                "baseline_ns": 3_000_000.0,
                "subject_ns": 3_600_000.0,
                "ratio": 1.2,
                "delta_pct": 20.0,
            }
        ],
        "verdict": {"status": "ok", "notes": []},
    }


class ResultSchemaTest(unittest.TestCase):
    def test_valid_result_passes(self) -> None:
        self.assertEqual(
            validate_instance(valid_result(), "result.schema.json"), []
        )

    def test_schema_version_is_frozen(self) -> None:
        result = valid_result()
        result["schema_version"] = 2
        self.assertTrue(validate_instance(result, "result.schema.json"))

    def test_missing_dataset_hash_is_rejected(self) -> None:
        result = valid_result()
        del result["experiment"]["dataset"]["sha256"]
        self.assertTrue(validate_instance(result, "result.schema.json"))

    def test_correct_implementation_needs_samples(self) -> None:
        result = valid_result()
        result["implementations"][0]["samples_ns"] = []
        self.assertTrue(validate_instance(result, "result.schema.json"))

    def test_failed_implementation_carries_no_samples(self) -> None:
        result = valid_result()
        implementation = result["implementations"][0]
        implementation["correctness"]["ok"] = False
        implementation["correctness"]["errors"] = ["sum differs by 4e-2"]
        implementation["samples_ns"] = []
        implementation["summary"] = None
        self.assertEqual(validate_instance(result, "result.schema.json"), [])

    def test_failed_implementation_with_samples_is_rejected(self) -> None:
        result = valid_result()
        implementation = result["implementations"][0]
        implementation["correctness"]["ok"] = False
        self.assertTrue(validate_instance(result, "result.schema.json"))

    def test_unknown_field_is_rejected(self) -> None:
        result = copy.deepcopy(valid_result())
        result["leaderboard_score"] = 42
        self.assertTrue(validate_instance(result, "result.schema.json"))

    def test_unknown_measurement_order_is_rejected(self) -> None:
        result = valid_result()
        result["experiment"]["measurement"]["order"] = "sequential"
        self.assertTrue(validate_instance(result, "result.schema.json"))


if __name__ == "__main__":
    unittest.main()


class ResultFileTest(unittest.TestCase):
    def test_valid_file_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "result.json"
            path.write_text(json.dumps(valid_result()), encoding="utf-8")
            self.assertEqual(validate_result_file(path), [])

    def test_broken_json_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "result.json"
            path.write_text("{not json", encoding="utf-8")
            problems = validate_result_file(path)
            self.assertEqual(len(problems), 1)
            self.assertIn("invalid JSON", problems[0])
