"""The schemas themselves are documents too: they must stay valid."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest

from jsonschema import Draft202012Validator

from mpf.specs import REPO_ROOT, SCHEMA_DIR, load_schema


class SchemaDocumentTest(unittest.TestCase):
    def test_schema_files_are_valid_json(self) -> None:
        paths = sorted(SCHEMA_DIR.glob("*.json"))
        self.assertTrue(paths, "schemas/ contains no schemas")
        for path in paths:
            with self.subTest(path=path.name):
                json.loads(path.read_text(encoding="utf-8"))

    def test_schemas_are_valid_draft_2020_12(self) -> None:
        for path in sorted(SCHEMA_DIR.glob("*.json")):
            with self.subTest(path=path.name):
                Draft202012Validator.check_schema(load_schema(path.name))


class CliSmokeTest(unittest.TestCase):
    def test_validate_command_passes_on_the_repository(self) -> None:
        completed = subprocess.run(
            [sys.executable, "-m", "mpf", "validate"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("numeric-scan", completed.stdout)


if __name__ == "__main__":
    unittest.main()
