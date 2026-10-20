"""Loading and validating MoonPerf Lab specifications.

Everything the repository promises about a workload is checked here: the
manifest against ``schemas/workload.schema.json``, every adapter against
``schemas/adapter.schema.json``, and the cross-file rules a JSON Schema cannot
express (the reference implementation exists, scripts are executable, ...).
"""

from __future__ import annotations

import json
import os
import re
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from jsonschema import Draft202012Validator, FormatChecker

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = REPO_ROOT / "schemas"
WORKLOADS_DIR = REPO_ROOT / "workloads"

WORKLOAD_MANIFEST = "workload.toml"
ADAPTER_MANIFEST = "adapter.toml"
RUN_SCRIPT = "run.sh"

IDENTIFIER = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
PARAM_KEY = re.compile(r"^[a-z][a-z0-9_]*$")


class SpecError(Exception):
    """A spec file could not be loaded or violates the experiment protocol."""


@dataclass(frozen=True)
class Implementation:
    """One language implementation of a workload, discovered on disk."""

    id: str
    directory: Path
    language: str
    summary: str | None


@dataclass(frozen=True)
class Workload:
    """A validated workload manifest plus its discovered implementations."""

    manifest_path: Path
    data: dict[str, Any]
    implementations: tuple[Implementation, ...]

    @property
    def directory(self) -> Path:
        return self.manifest_path.parent

    @property
    def name(self) -> str:
        return str(self.data["name"])

    @property
    def version(self) -> int:
        return int(self.data["version"])

    @property
    def tier(self) -> str:
        return str(self.data["tier"])

    @property
    def status(self) -> str:
        return str(self.data.get("status", "draft"))


_SCHEMAS: dict[str, dict[str, Any]] = {}


def load_schema(name: str) -> dict[str, Any]:
    """Load a JSON Schema from ``schemas/`` by file name."""

    if name not in _SCHEMAS:
        path = SCHEMA_DIR / name
        try:
            with path.open(encoding="utf-8") as fh:
                _SCHEMAS[name] = json.load(fh)
        except OSError as exc:
            raise SpecError(f"{path}: cannot read schema: {exc.strerror}") from exc
        except json.JSONDecodeError as exc:
            raise SpecError(f"{path}: invalid JSON in schema: {exc}") from exc
    return _SCHEMAS[name]


def validate_instance(instance: Any, schema_name: str) -> list[str]:
    """Return human-readable violations of ``instance`` against a schema."""

    validator = Draft202012Validator(
        load_schema(schema_name), format_checker=FormatChecker()
    )
    errors = sorted(
        validator.iter_errors(instance),
        key=lambda error: (list(error.absolute_path), error.message),
    )
    return [_describe(error) for error in errors]


def load_toml(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError as exc:
        raise SpecError(f"{path}: no such file") from exc
    except tomllib.TOMLDecodeError as exc:
        raise SpecError(f"{path}: invalid TOML: {exc}") from exc
    except OSError as exc:
        raise SpecError(f"{path}: {exc.strerror}") from exc


def discover_workload_paths(root: Path | None = None) -> list[Path]:
    """Every ``workloads/*/workload.toml``, sorted by path."""

    base = WORKLOADS_DIR if root is None else root
    return sorted(base.glob("*/workload.toml"))


def discover_implementations(
    workload_dir: Path,
) -> tuple[list[Implementation], list[str]]:
    """Discover implementations and collect per-file problems instead of raising.

    A workload without an ``implementations/`` directory is a valid draft; it
    simply has no implementations yet.
    """

    base = workload_dir / "implementations"
    implementations: list[Implementation] = []
    problems: list[str] = []
    if not base.is_dir():
        return implementations, problems

    for entry in sorted(base.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        if not IDENTIFIER.fullmatch(entry.name):
            problems.append(
                f"{entry}: implementation directory names must match "
                "'^[a-z][a-z0-9]*(-[a-z0-9]+)*$'"
            )
            continue

        adapter_path = entry / ADAPTER_MANIFEST
        if not adapter_path.is_file():
            problems.append(f"{entry}: missing {ADAPTER_MANIFEST}")
            continue
        try:
            adapter = load_toml(adapter_path)
        except SpecError as exc:
            problems.append(str(exc))
            continue
        for error in validate_instance(adapter, "adapter.schema.json"):
            problems.append(f"{adapter_path}: {error}")

        run_script = entry / RUN_SCRIPT
        if not run_script.is_file():
            problems.append(f"{entry}: missing {RUN_SCRIPT}")
        elif not os.access(run_script, os.X_OK):
            problems.append(f"{run_script}: not executable (chmod +x it)")

        implementations.append(
            Implementation(
                id=entry.name,
                directory=entry,
                language=str(adapter.get("language", "")),
                summary=adapter.get("summary"),
            )
        )
    return implementations, problems


def load_workload(manifest_path: Path) -> Workload:
    """Load, schema-validate and cross-check one workload manifest."""

    manifest_path = Path(manifest_path)
    data = load_toml(manifest_path)
    errors = validate_instance(data, "workload.schema.json")
    implementations, problems = discover_implementations(manifest_path.parent)

    problems.extend(errors)
    problems.extend(_semantic_problems(data, implementations))
    if problems:
        raise SpecError(
            "\n".join(f"{manifest_path}: {problem}" for problem in problems)
        )
    return Workload(manifest_path, data, tuple(implementations))


def _semantic_problems(
    data: dict[str, Any], implementations: Sequence[Implementation]
) -> list[str]:
    problems: list[str] = []
    status = str(data.get("status", "draft"))
    reference = data.get("verify", {}).get("reference")

    if status == "active" and not implementations:
        problems.append(
            "status is 'active' but no implementations were discovered"
        )
    if implementations:
        ids = {implementation.id for implementation in implementations}
        if reference is None:
            problems.append(
                "verify.reference is required once implementations exist"
            )
        elif reference not in ids:
            problems.append(
                f"verify.reference '{reference}' is not a discovered implementation "
                f"(found: {', '.join(sorted(ids))})"
            )

    for key, value in data.get("params", {}).items():
        if not PARAM_KEY.fullmatch(key):
            problems.append(
                f"params.{key}: parameter names must match '^[a-z][a-z0-9_]*$'"
            )
        if isinstance(value, str) and ("\n" in value or "\r" in value):
            problems.append(
                f"params.{key}: string parameters must be single-line"
            )
    return problems


def validate_result_file(path: Path) -> list[str]:
    """Validate one result artifact; return ``path: violation`` strings."""

    path = Path(path)
    try:
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        return [f"{path}: invalid JSON: {exc}"]
    except OSError as exc:
        return [f"{path}: {exc.strerror}"]
    return [f"{path}: {error}" for error in validate_instance(data, "result.schema.json")]


def _describe(error: Any) -> str:
    location = ".".join(str(part) for part in error.absolute_path) or "<root>"
    return f"{location}: {error.message}"
