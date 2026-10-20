"""Execute one workload and record the experiment artifact.

The runner is the only component that produces numbers. For every
implementation it builds from clean, verifies the output against the reference,
then measures the valid ones in round-robin order. The result is a JSON
artifact (the source of truth) plus a Markdown report generated from it.

Contract: ``docs/experiment-protocol.md`` sections 5 to 9.
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import signal
import statistics
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence

from mpf import __version__
from mpf.dataset import Dataset, ensure_dataset, render_params
from mpf.report import render_report, research_question
from mpf.specs import (
    REPO_ROOT,
    Implementation,
    SpecError,
    Workload,
    load_workload,
)

BUILD_TIMEOUT_S = 900.0
DESCRIBE_TIMEOUT_S = 60.0
LOG_TAIL_CHARS = 4000


class RunError(SpecError):
    """The experiment could not produce an admissible artifact."""


@dataclass
class CommandResult:
    ok: bool
    exit_code: int | None
    duration_ms: float
    stdout: str = ""
    stderr: str = ""
    timed_out: bool = False

    @property
    def combined(self) -> str:
        parts = [part for part in (self.stdout, self.stderr) if part]
        return "".join(parts)


@dataclass
class ImplementationRun:
    """Mutable measurement state for one implementation."""

    impl: Implementation
    build_ok: bool = False
    build_skipped: bool = False
    build_command: str | None = None
    build_duration_ms: float = 0.0
    build_log_sha256: str | None = None
    build_log_tail: str = ""
    toolchain: str | None = None
    correctness_ok: bool = False
    correctness_values: dict[str, Any] = field(default_factory=dict)
    correctness_errors: list[str] = field(default_factory=list)
    output_sha256: str | None = None
    samples_ns: list[int] = field(default_factory=list)
    summary: dict[str, Any] | None = None

@dataclass
class RunReport:
    artifact: dict[str, Any]
    artifact_path: Path
    report_path: Path

    @property
    def verdict(self) -> str:
        return str(self.artifact["verdict"]["status"])


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _isoformat(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def _sha256(data: bytes | str) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8", "replace")
    return hashlib.sha256(data).hexdigest()


def run_command(
    args: Sequence[str],
    cwd: Path,
    timeout_s: float,
    env: dict[str, str] | None = None,
) -> CommandResult:
    """Run one child process, capturing output and enforcing a timeout."""

    started = time.monotonic()
    try:
        process = subprocess.Popen(
            list(args),
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=dict(os.environ) if env is None else env,
            start_new_session=True,
        )
    except OSError as exc:
        return CommandResult(
            ok=False,
            exit_code=None,
            duration_ms=0.0,
            stderr=f"cannot start {args[0]}: {exc.strerror}",
        )

    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        timed_out = True
        _kill_process_group(process)
        stdout, stderr = process.communicate()
    duration_ms = (time.monotonic() - started) * 1000.0
    return CommandResult(
        ok=not timed_out and process.returncode == 0,
        exit_code=process.returncode,
        duration_ms=duration_ms,
        stdout=stdout or "",
        stderr=stderr or "",
        timed_out=timed_out,
    )


def _kill_process_group(process: subprocess.Popen[str]) -> None:
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        process.kill()


def capture_environment() -> dict[str, Any]:
    """The machine and OS facts every artifact must carry (protocol section 8)."""

    os_name = platform.system() or "unknown"
    os_release = ""
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if line.startswith("PRETTY_NAME="):
                os_release = line.split("=", 1)[1].strip().strip('"')
                break
    except OSError:
        os_release = platform.release()

    cpu_model = ""
    logical_cpus = os.cpu_count() or 1
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8").splitlines():
            if line.lower().startswith("model name"):
                cpu_model = line.split(":", 1)[1].strip()
                break
    except OSError:
        cpu_model = platform.processor() or "unknown"

    governor: str | None = None
    try:
        governor = Path(
            "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        ).read_text(encoding="utf-8").strip() or None
    except OSError:
        governor = None

    try:
        memory_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except (ValueError, OSError):
        memory_bytes = 1

    return {
        "os": os_name,
        "os_release": os_release,
        "arch": platform.machine() or "unknown",
        "cpu": {
            "model": cpu_model or "unknown",
            "logical_cpus": logical_cpus,
            "governor": governor,
        },
        "memory_bytes": int(memory_bytes),
    }


def _git_output(args: Sequence[str]) -> str | None:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def capture_source() -> dict[str, Any]:
    """Commit, branch and dirty flag: which code produced the numbers."""

    commit = _git_output(["rev-parse", "HEAD"])
    if commit is not None and len(commit) != 40:
        commit = None
    branch = _git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    status = _git_output(["status", "--porcelain"])
    return {
        "commit": commit,
        "dirty": bool(status),
        "branch": branch,
    }


def _toolchain(run: ImplementationRun) -> str | None:
    script = run.impl.directory / "describe.sh"
    if not script.is_file():
        return None
    result = run_command([str(script)], cwd=run.impl.directory, timeout_s=DESCRIBE_TIMEOUT_S)
    if not result.ok:
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    value = payload.get("toolchain") if isinstance(payload, dict) else None
    return value if isinstance(value, str) else None


def _build(run: ImplementationRun) -> None:
    run.toolchain = _toolchain(run)
    script = run.impl.directory / "build.sh"
    if not script.is_file():
        run.build_ok = True
        run.build_skipped = True
        return
    result = run_command([str(script)], cwd=run.impl.directory, timeout_s=BUILD_TIMEOUT_S)
    run.build_ok = result.ok
    run.build_command = "./build.sh"
    run.build_duration_ms = round(result.duration_ms, 3)
    log = result.combined
    run.build_log_sha256 = _sha256(log)
    run.build_log_tail = log[-LOG_TAIL_CHARS:]


def _invoke(
    run: ImplementationRun,
    dataset: Dataset,
    params_path: Path,
    output_path: Path,
    repeat: int,
    timeout_s: float,
) -> CommandResult:
    return run_command(
        [
            str(run.impl.directory / "run.sh"),
            "--input",
            str(dataset.path),
            "--params",
            str(params_path),
            "--output",
            str(output_path),
            "--repeat",
            str(repeat),
        ],
        cwd=run.impl.directory,
        timeout_s=timeout_s,
    )


def _json_type(value: Any) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if value is None:
        return "null"
    return type(value).__name__


def _scalar(value: Any) -> bool:
    return isinstance(value, (bool, int, float, str))


def read_output(
    path: Path, fields: Sequence[str]
) -> tuple[dict[str, Any], list[str]]:
    """Parse one adapter output object and check its declared fields."""

    errors: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return {}, [f"no output file: {exc.strerror}"]
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        return {}, [f"invalid JSON output: {exc}"]
    if not isinstance(payload, dict):
        return {}, [f"output must be a JSON object, got {_json_type(payload)}"]
    values: dict[str, Any] = {}
    for field_name in fields:
        if field_name not in payload:
            errors.append(f"missing field '{field_name}'")
            continue
        value = payload[field_name]
        if not _scalar(value):
            errors.append(
                f"field '{field_name}' must be a scalar, got {_json_type(value)}"
            )
            continue
        values[field_name] = value
    return values, errors


def compare_values(
    subject: dict[str, Any],
    reference: dict[str, Any],
    fields: Sequence[str],
    mode: str,
    rtol: float,
    atol: float,
) -> list[str]:
    """The correctness gate: exact for exact mode, tolerance for floats."""

    errors: list[str] = []
    for field_name in fields:
        if field_name not in subject:
            errors.append(f"{field_name}: missing from the subject output")
            continue
        if field_name not in reference:
            errors.append(f"{field_name}: missing from the reference output")
            continue
        subject_value = subject[field_name]
        reference_value = reference[field_name]
        subject_type = _json_type(subject_value)
        reference_type = _json_type(reference_value)

        if mode == "exact":
            if subject_type != reference_type:
                errors.append(
                    f"{field_name}: type mismatch ({subject_type} vs reference "
                    f"{reference_type})"
                )
            elif subject_value != reference_value:
                errors.append(
                    f"{field_name}: {subject_value!r} != reference {reference_value!r}"
                )
            continue

        # tolerance mode: only IEEE-754 fields are compared approximately.
        if reference_type != "number":
            if subject_type != reference_type:
                errors.append(
                    f"{field_name}: type mismatch ({subject_type} vs reference "
                    f"{reference_type})"
                )
            elif subject_value != reference_value:
                errors.append(
                    f"{field_name}: {subject_value!r} != reference {reference_value!r}"
                )
            continue

        if subject_type != "number":
            errors.append(
                f"{field_name}: type mismatch ({subject_type} vs reference number)"
            )
            continue
        delta = abs(float(subject_value) - float(reference_value))
        limit = atol + rtol * abs(float(reference_value))
        if delta > limit:
            errors.append(
                f"{field_name}: |{subject_value} - {reference_value}| = {delta:.6g} "
                f"exceeds tolerance {limit:.6g}"
            )
    return errors


def summarize(samples: Sequence[int]) -> dict[str, Any] | None:
    if not samples:
        return None
    count = len(samples)
    mean = statistics.mean(samples)
    stdev = statistics.stdev(samples) if count > 1 else 0.0
    return {
        "count": count,
        "min_ns": min(samples),
        "median_ns": statistics.median(samples),
        "mean_ns": mean,
        "stdev_ns": stdev,
        "cv": (stdev / mean) if mean else 0.0,
    }


def run_workload(
    workload_path: Path,
    out_dir: Path | None = None,
    data_dir: Path | None = None,
) -> RunReport:
    """Run one workload end to end and commit-free record the artifact."""

    workload_path = Path(workload_path)
    if workload_path.is_dir():
        workload_path = workload_path / "workload.toml"
    workload = load_workload(workload_path)

    implementations = list(workload.implementations)
    if not implementations:
        raise RunError(
            f"{workload.name}: no implementations under "
            f"{workload.directory / 'implementations'}"
        )
    if workload.status == "retired":
        raise RunError(f"{workload.name}: retired workloads are not measured")

    verify = workload.data["verify"]
    reference_id = verify.get("reference")
    if reference_id is None:
        raise RunError(f"{workload.name}: verify.reference is required to run")
    fields = list(verify["fields"])
    mode = str(verify["mode"])
    rtol = float(verify.get("rtol", 0.0))
    atol = float(verify.get("atol", 0.0))
    if mode == "tolerance" and "rtol" not in verify:
        raise RunError(f"{workload.name}: tolerance mode requires verify.rtol")

    measurement = workload.data["measurement"]
    warmup = int(measurement["warmup"])
    repeats = int(measurement["repeats"])
    timeout_s = float(measurement["timeout_s"])
    inner_repeats = int(measurement["inner_repeats"])
    max_cv = float(measurement.get("max_cv", 0.05))

    dataset = ensure_dataset(workload, data_dir=data_dir)
    started_at = utc_now()
    stamp = started_at.strftime("%Y%m%dT%H%M%SZ")
    source = capture_source()
    commit12 = source["commit"][:12] if source["commit"] else "nogit"

    runs: dict[str, ImplementationRun] = {
        implementation.id: ImplementationRun(implementation)
        for implementation in implementations
    }
    verdict_notes: list[str] = []

    with tempfile.TemporaryDirectory(prefix="mpf-run-") as tmp:
        tmp_dir = Path(tmp)
        params_path = tmp_dir / "params.txt"
        params_path.write_text(render_params(workload.data.get("params", {})), encoding="utf-8")

        # 1. Build every implementation from clean and record the result.
        for run in runs.values():
            _build(run)
            if not run.build_ok:
                verdict_notes.append(f"build failed: {run.impl.id}")

        # 2. Correctness gate, reference first: its output is ground truth.
        # The reference must be verified before any subject, regardless of the
        # alphabetical discovery order. Otherwise a subject that sorts before
        # the reference is rejected with "reference did not pass".
        reference_values: dict[str, Any] | None = None
        reference_run = runs.get(reference_id)
        if reference_run is None:
            raise RunError(
                f"{workload.name}: reference '{reference_id}' is not a discovered "
                "implementation"
            )
        verification_order = [reference_run]
        verification_order.extend(
            run for run in runs.values() if run is not reference_run
        )
        for run in verification_order:
            output_path = tmp_dir / f"{run.impl.id}-correctness.json"
            if not run.build_ok:
                run.correctness_ok = False
                run.correctness_errors = ["build failed, correctness not run"]
                continue
            result = _invoke(run, dataset, params_path, output_path, inner_repeats, timeout_s)
            if result.timed_out:
                run.correctness_errors = [f"correctness run timed out after {timeout_s}s"]
                continue
            if not result.ok:
                tail = result.combined.strip()[-1000:]
                run.correctness_errors = [
                    f"correctness run exited {result.exit_code}"
                    + (f": {tail}" if tail else "")
                ]
                continue
            run.output_sha256 = _sha256(output_path.read_bytes()) if output_path.is_file() else None
            values, errors = read_output(output_path, fields)
            if run is reference_run:
                run.correctness_values = values
                run.correctness_errors = errors
                run.correctness_ok = not errors
                if run.correctness_ok:
                    reference_values = dict(values)
                continue
            if reference_values is None:
                run.correctness_errors = [
                    f"reference implementation '{reference_id}' did not pass, "
                    "so this implementation cannot be verified"
                ]
                continue
            run.correctness_values = values
            comparison_errors = list(errors) + compare_values(
                values, reference_values, fields, mode, rtol, atol
            )
            run.correctness_errors = comparison_errors
            run.correctness_ok = not comparison_errors

        if reference_values is None:
            verdict_notes.append(
                f"reference implementation '{reference_id}' failed the correctness gate"
            )

        for run in runs.values():
            if not run.correctness_ok:
                verdict_notes.append(f"correctness failed: {run.impl.id}")

        # 3. Measure only implementations that passed the gate.
        valid = [
            run
            for run in runs.values()
            if run.correctness_ok and run.build_ok
        ]
        for _ in range(warmup if valid else 0):
            for run in valid:
                output_path = tmp_dir / f"{run.impl.id}-warmup.json"
                result = _invoke(run, dataset, params_path, output_path, inner_repeats, timeout_s)
                _require_measurement(run, result, timeout_s, "warmup")

        sampled: dict[str, list[int]] = {run.impl.id: [] for run in valid}
        for round_index in range(repeats if valid else 0):
            rotation = round_index % len(valid)
            order = valid[rotation:] + valid[:rotation]
            for run in order:
                output_path = tmp_dir / f"{run.impl.id}-sample-{round_index}.json"
                started_ns = time.monotonic_ns()
                result = _invoke(run, dataset, params_path, output_path, inner_repeats, timeout_s)
                wall_ns = time.monotonic_ns() - started_ns
                _require_measurement(run, result, timeout_s, f"round {round_index + 1}")
                sampled[run.impl.id].append(wall_ns // inner_repeats)

        verdict_status = "ok"
        for run in runs.values():
            if not run.correctness_ok:
                continue
            run.samples_ns = sampled.get(run.impl.id, [])
            run.summary = summarize(run.samples_ns)
            if run.summary is not None and run.summary["cv"] > max_cv:
                verdict_status = "unstable"
                verdict_notes.append(
                    f"coefficient of variation {run.summary['cv']:.3f} exceeds "
                    f"max_cv {max_cv}: {run.impl.id}"
                )

        if any(not run.correctness_ok for run in runs.values()):
            verdict_status = "invalid"
        if reference_values is None:
            verdict_status = "invalid"

        comparisons: list[dict[str, Any]] = []
        if verdict_status == "ok" and reference_values is not None:
            baseline_run = runs[reference_id]
            baseline_summary = baseline_run.summary
            if baseline_summary is not None:
                for run in runs.values():
                    if run.impl.id == reference_id or run.summary is None:
                        continue
                    baseline_ns = float(baseline_summary["median_ns"])
                    subject_ns = float(run.summary["median_ns"])
                    ratio = subject_ns / baseline_ns if baseline_ns else 0.0
                    comparisons.append(
                        {
                            "baseline": reference_id,
                            "subject": run.impl.id,
                            "metric": "median_ns",
                            "baseline_ns": baseline_ns,
                            "subject_ns": subject_ns,
                            "ratio": ratio,
                            "delta_pct": (ratio - 1.0) * 100.0,
                        }
                    )

        artifact: dict[str, Any] = {
            "schema_version": 1,
            "experiment": {
                "id": f"{stamp}-{commit12}",
                "started_at": _isoformat(started_at),
                "finished_at": _isoformat(utc_now()),
                "harness": {
                    "name": "mpf",
                    "version": __version__,
                    "runtime": f"Python {platform.python_version()}",
                },
                "source": source,
                "workload": {
                    "name": workload.name,
                    "version": workload.version,
                    "tier": workload.tier,
                    "manifest_sha256": _sha256(workload.manifest_path.read_bytes()),
                },
                "dataset": {
                    "generator": dataset.generator,
                    "count": dataset.count,
                    "seed": dataset.seed,
                    "params": dataset.params,
                    "sha256": dataset.sha256,
                    "bytes": dataset.byte_size,
                },
                "params": dict(workload.data.get("params", {})),
                "measurement": {
                    "warmup": warmup,
                    "repeats": repeats,
                    "timeout_s": timeout_s,
                    "inner_repeats": inner_repeats,
                    "max_cv": max_cv,
                    "order": "round-robin",
                    "clock": "monotonic",
                },
                "environment": capture_environment(),
                "reproduce_command": _reproduce_command(workload),
            },
            "implementations": [
                _implementation_payload(run, reference_id, mode)
                for run in runs.values()
            ],
            "comparisons": comparisons,
            "verdict": {"status": verdict_status, "notes": verdict_notes},
        }

        destination = out_dir if out_dir is not None else REPO_ROOT / "results" / workload.name
        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True)
        artifact_path = destination / f"{stamp}-{commit12}.json"
        report_path = artifact_path.with_suffix(".md")

        artifact_path.write_text(
            json.dumps(artifact, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        report_path.write_text(
            render_report(artifact, research_question(workload)), encoding="utf-8"
        )

    return RunReport(artifact=artifact, artifact_path=artifact_path, report_path=report_path)


def _require_measurement(
    run: ImplementationRun, result: CommandResult, timeout_s: float, phase: str
) -> None:
    if result.timed_out:
        raise RunError(
            f"{run.impl.id}: {phase} timed out after {timeout_s}s "
            f"(a timeout is a failed run, not a slow sample)"
        )
    if not result.ok:
        tail = result.combined.strip()[-1000:]
        raise RunError(
            f"{run.impl.id}: {phase} failed with exit code {result.exit_code}"
            + (f": {tail}" if tail else "")
        )


def _implementation_payload(
    run: ImplementationRun, reference_id: str, mode: str
) -> dict[str, Any]:
    return {
        "id": run.impl.id,
        "language": run.impl.language,
        "reference": run.impl.id == reference_id,
        "toolchain": run.toolchain,
        "build": {
            "ok": run.build_ok,
            "skipped": run.build_skipped,
            "command": run.build_command,
            "duration_ms": run.build_duration_ms,
            "log_sha256": run.build_log_sha256,
            "log_tail": run.build_log_tail,
        },
        "correctness": {
            "ok": run.correctness_ok,
            "mode": mode,
            "checked_against": None
            if run.impl.id == reference_id
            else reference_id,
            "output_sha256": run.output_sha256,
            "values": run.correctness_values,
            "errors": run.correctness_errors,
        },
        "samples_ns": run.samples_ns if run.correctness_ok else [],
        "summary": run.summary if run.correctness_ok else None,
    }


def _reproduce_command(workload: Workload) -> str:
    try:
        relative = workload.directory.relative_to(REPO_ROOT)
    except ValueError:
        relative = workload.directory
    return f"uv run mpf run {relative}"


