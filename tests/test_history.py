"""History index tests: derived data must agree with the artifacts it summarizes."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from mpf.specs import (
    REPO_ROOT,
    _host_profile,
    _slug,
    validate_history_file,
)

RESULTS = REPO_ROOT / "results"
# The gather workload has one artifact, which keeps every fixture below small.
ARTIFACT = "20261021T140344Z-b6d5f9215963.json"


def _committed_indexes() -> list[Path]:
    return sorted(RESULTS.rglob("index.json"))


class CommittedHistoryTest(unittest.TestCase):
    def test_every_committed_index_validates(self) -> None:
        indexes = _committed_indexes()
        self.assertTrue(indexes, "results/ holds no history index")
        for path in indexes:
            with self.subTest(path=path):
                self.assertEqual(validate_history_file(path), [])

    def test_every_results_directory_has_an_index(self) -> None:
        directories = sorted(
            directory
            for directory in RESULTS.iterdir()
            if directory.is_dir() and directory.name != "tmp"
        )
        self.assertTrue(directories)
        for directory in directories:
            with self.subTest(directory=directory):
                self.assertTrue((directory / "index.json").is_file())


class HostProfileTest(unittest.TestCase):
    def test_slug_drops_marketing_marks(self) -> None:
        self.assertEqual(_slug("Intel(R) Core(TM) i5-12500H"), "intel-core-i5-12500h")
        self.assertEqual(_slug("x86_64"), "x86-64")
        self.assertEqual(_slug("  spaced   out  "), "spaced-out")

    def test_missing_governor_is_not_guessed(self) -> None:
        environment = {
            "os": "Linux",
            "arch": "x86_64",
            "cpu": {"model": "demo cpu", "logical_cpus": 8},
        }
        self.assertEqual(_host_profile(environment), "linux-x86-64-demo-cpu-8c-unknown")


class HistoryDriftTest(unittest.TestCase):
    def _fixture(self, root: Path) -> Path:
        directory = root / "gather"
        directory.mkdir()
        shutil.copy(RESULTS / "gather" / ARTIFACT, directory / ARTIFACT)
        shutil.copy(RESULTS / "gather" / "index.json", directory / "index.json")
        return directory

    def test_the_fixture_itself_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            self.assertEqual(validate_history_file(directory / "index.json"), [])

    def test_a_changed_measurement_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            index_path = directory / "index.json"
            data = json.loads(index_path.read_text(encoding="utf-8"))
            data["entries"][0]["implementations"][0]["median_ns"] = 1.0
            index_path.write_text(json.dumps(data), encoding="utf-8")
            problems = validate_history_file(index_path)
            self.assertTrue(
                any("does not match the artifacts" in problem for problem in problems),
                problems,
            )

    def test_an_unindexed_artifact_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            shutil.copy(RESULTS / "gather" / ARTIFACT, directory / "extra.json")
            problems = validate_history_file(directory / "index.json")
            self.assertTrue(
                any("not indexed" in problem for problem in problems), problems
            )

    def test_a_missing_artifact_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            (directory / ARTIFACT).unlink()
            problems = validate_history_file(directory / "index.json")
            self.assertTrue(
                any("do not exist" in problem for problem in problems), problems
            )

    def test_a_misnamed_directory_is_caught(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            renamed = directory.parent / "other"
            directory.rename(renamed)
            problems = validate_history_file(renamed / "index.json")
            self.assertTrue(
                any("must match the results directory" in problem for problem in problems),
                problems,
            )

    def test_an_unknown_verdict_is_rejected_by_the_schema(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            index_path = directory / "index.json"
            data = json.loads(index_path.read_text(encoding="utf-8"))
            data["entries"][0]["verdict"] = "great"
            index_path.write_text(json.dumps(data), encoding="utf-8")
            problems = validate_history_file(index_path)
            self.assertTrue(
                any("verdict" in problem for problem in problems), problems
            )

    def test_a_missing_index_file_is_reported_not_crashed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = self._fixture(Path(tmp))
            problems = validate_history_file(directory / "absent.json")
            self.assertEqual(len(problems), 1)
            self.assertIn("cannot load history index", problems[0])


if __name__ == "__main__":
    unittest.main()
