"""Specification tests: manifests, adapters and the cross-file rules."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from mpf.specs import (
    REPO_ROOT,
    SpecError,
    discover_workload_paths,
    load_workload,
    validate_instance,
)

MANIFEST = """\
schema_version = 1
name = "demo-scan"
version = 1
status = "draft"
tier = "micro"
summary = "demo workload used by the test suite"

[dataset]
generator = "uniform-f64"
count = 16
seed = 1

[dataset.params]
min = -1.0
max = 1.0

[verify]
mode = "exact"
fields = ["n"]
reference = "rust"

[measurement]
warmup = 0
repeats = 1
timeout_s = 10
inner_repeats = 1
"""

MATRIX = """
[matrix.half]
status = "probe"
description = "Half the values."
count = 8
"""

EMPTY_VARIANT = """
[matrix.empty]
status = "probe"
description = "Nothing changes."
"""


def _manifest_dict() -> dict:
    return {
        "schema_version": 1,
        "name": "demo-scan",
        "version": 1,
        "status": "draft",
        "tier": "micro",
        "summary": "demo workload used by the test suite",
        "dataset": {"generator": "uniform-f64", "count": 16, "seed": 1},
        "params": {"threshold": 0.0},
        "verify": {"mode": "exact", "fields": ["n"], "reference": "rust"},
        "measurement": {
            "warmup": 0,
            "repeats": 1,
            "timeout_s": 10,
            "inner_repeats": 1,
        },
    }


class CommittedSpecTest(unittest.TestCase):
    def test_every_committed_workload_is_valid(self) -> None:
        paths = discover_workload_paths()
        self.assertTrue(paths, "workloads/ contains no workloads")
        for path in paths:
            with self.subTest(path=path):
                workload = load_workload(path)
                self.assertTrue(workload.name)
                self.assertIn(workload.tier, {"micro", "component", "end-to-end"})


class WorkloadSchemaTest(unittest.TestCase):
    def test_baseline_manifest_is_valid(self) -> None:
        self.assertEqual(validate_instance(_manifest_dict(), "workload.schema.json"), [])

    def test_unknown_tier_is_rejected(self) -> None:
        data = _manifest_dict()
        data["tier"] = "unit"
        self.assertTrue(validate_instance(data, "workload.schema.json"))

    def test_missing_dataset_is_rejected(self) -> None:
        data = _manifest_dict()
        del data["dataset"]
        errors = validate_instance(data, "workload.schema.json")
        self.assertTrue(any("dataset" in error for error in errors))

    def test_tolerance_requires_rtol(self) -> None:
        data = _manifest_dict()
        data["verify"] = {"mode": "tolerance", "fields": ["n"]}
        errors = validate_instance(data, "workload.schema.json")
        self.assertTrue(any("rtol" in error for error in errors))

    def test_unknown_field_is_rejected(self) -> None:
        data = _manifest_dict()
        data["benchmark_timeout"] = 10
        self.assertTrue(validate_instance(data, "workload.schema.json"))


class AdapterSchemaTest(unittest.TestCase):
    def test_adapter_requires_language(self) -> None:
        adapter = {"schema_version": 1}
        self.assertTrue(validate_instance(adapter, "adapter.schema.json"))

    def test_valid_adapter_passes(self) -> None:
        adapter = {"schema_version": 1, "language": "Rust", "summary": "reference"}
        self.assertEqual(validate_instance(adapter, "adapter.schema.json"), [])

    def test_optional_build_dir_passes(self) -> None:
        adapter = {
            "schema_version": 1,
            "language": "MoonBit",
            "build_dir": "_build",
        }
        self.assertEqual(validate_instance(adapter, "adapter.schema.json"), [])


class WorkloadSemanticsTest(unittest.TestCase):
    def _make_workload(self, root: Path) -> Path:
        workload_dir = root / "demo-scan"
        workload_dir.mkdir()
        (workload_dir / "workload.toml").write_text(MANIFEST, encoding="utf-8")
        return workload_dir

    def _add_implementation(
        self, workload_dir: Path, implementation_id: str = "rust"
    ) -> Path:
        implementation_dir = workload_dir / "implementations" / implementation_id
        implementation_dir.mkdir(parents=True)
        (implementation_dir / "adapter.toml").write_text(
            'schema_version = 1\nlanguage = "Rust"\n', encoding="utf-8"
        )
        run_script = implementation_dir / "run.sh"
        run_script.write_text("#!/bin/sh\necho ok\n", encoding="utf-8")
        run_script.chmod(0o755)
        return implementation_dir

    def test_draft_without_implementations_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            workload = load_workload(workload_dir / "workload.toml")
            self.assertEqual(workload.implementations, ())

    def test_implementation_is_discovered(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            self._add_implementation(workload_dir)
            workload = load_workload(workload_dir / "workload.toml")
            self.assertEqual([item.id for item in workload.implementations], ["rust"])
            self.assertEqual(workload.implementations[0].language, "Rust")

    def test_missing_run_script_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            implementation_dir = self._add_implementation(workload_dir)
            (implementation_dir / "run.sh").unlink()
            with self.assertRaises(SpecError):
                load_workload(workload_dir / "workload.toml")

    @unittest.skipUnless(os.name == "posix", "executable bits are POSIX-only")
    def test_non_executable_run_script_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            implementation_dir = self._add_implementation(workload_dir)
            (implementation_dir / "run.sh").chmod(0o644)
            with self.assertRaises(SpecError):
                load_workload(workload_dir / "workload.toml")

    def test_reference_must_name_a_discovered_implementation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            self._add_implementation(workload_dir, "moonbit")
            with self.assertRaises(SpecError):
                load_workload(workload_dir / "workload.toml")

    def test_name_must_match_the_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace('name = "demo-scan"', 'name = "other-scan"'),
                encoding="utf-8",
            )
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("must match the workload directory", str(raised.exception))

    def test_unknown_dataset_generator_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace('generator = "uniform-f64"', 'generator = "uniform-f32"'),
                encoding="utf-8",
            )
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("not a built-in generator", str(raised.exception))

    def test_uniform_f64_requires_bounded_params(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace(
                    "[dataset.params]\nmin = -1.0\nmax = 1.0\n\n", ""
                ),
                encoding="utf-8",
            )
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("dataset.params.min", str(raised.exception))

    @unittest.skipUnless(os.name == "posix", "executable bits are POSIX-only")
    def test_non_executable_build_script_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            implementation_dir = self._add_implementation(workload_dir)
            build_script = implementation_dir / "build.sh"
            build_script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            build_script.chmod(0o644)
            with self.assertRaises(SpecError) as raised:
                load_workload(workload_dir / "workload.toml")
            self.assertIn("not executable", str(raised.exception))

    def test_active_workload_needs_implementations(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace('status = "draft"', 'status = "active"'),
                encoding="utf-8",
            )
            with self.assertRaises(SpecError):
                load_workload(manifest_path)

    def test_active_workload_needs_an_input_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            self._add_implementation(workload_dir)
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace('status = "draft"', 'status = "active"'),
                encoding="utf-8",
            )
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("no input matrix", str(raised.exception))

    def test_active_workload_with_an_input_matrix_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            self._add_implementation(workload_dir)
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST.replace('status = "draft"', 'status = "active"')
                + MATRIX,
                encoding="utf-8",
            )
            workload = load_workload(manifest_path)
            self.assertEqual(sorted(workload.data["matrix"]), ["half"])

    def test_variant_must_override_something(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(MANIFEST + EMPTY_VARIANT, encoding="utf-8")
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("override at least one", str(raised.exception))

    def test_variant_must_stay_a_valid_uniform_f64_dataset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST
                + """
[matrix.inverted]
status = "probe"
description = "An inverted range is not a uniform-f64 dataset."

[matrix.inverted.dataset_params]
min = 1.0
max = -1.0
""",
                encoding="utf-8",
            )
            with self.assertRaises(SpecError) as raised:
                load_workload(manifest_path)
            self.assertIn("merged dataset.params.min", str(raised.exception))

    def test_variant_shape_is_schema_checked(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workload_dir = self._make_workload(Path(tmp))
            manifest_path = workload_dir / "workload.toml"
            manifest_path.write_text(
                MANIFEST
                + '[matrix.half]\nstatus = "maybe"\ndescription = "x"\ncount = 8\n',
                encoding="utf-8",
            )
            with self.assertRaises(SpecError):
                load_workload(manifest_path)


if __name__ == "__main__":
    unittest.main()
