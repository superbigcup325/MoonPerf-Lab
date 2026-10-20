"""Deterministic dataset generation (protocol section 4).

The harness owns the dataset: implementations only read the file, and the
result artifact records its SHA-256 so two runs can prove they used the same
input. A generator is a pure function of ``(count, seed, params)``; its
algorithm never changes under the same id.
"""

from __future__ import annotations

import hashlib
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from mpf.specs import (
    REPO_ROOT,
    SUPPORTED_GENERATORS,
    SpecError,
    Workload,
)

MASK64 = (1 << 64) - 1
GOLDEN_GAMMA = 0x9E3779B97F4A7C15
MIX_1 = 0xBF58476D1CE4E5B9
MIX_2 = 0x94D049BB133111EB
SCALE_2_POW_MINUS_53 = 2.0**-53


@dataclass(frozen=True)
class Dataset:
    """A generated input file plus the identity recorded in every artifact."""

    path: Path
    generator: str
    count: int
    seed: int
    params: dict[str, Any]
    sha256: str
    byte_size: int


def render_params(params: dict[str, Any]) -> str:
    """The adapter params file: one ``key=value`` line per parameter, sorted."""

    lines: list[str] = []
    for key in sorted(params):
        value = params[key]
        if isinstance(value, bool):
            text = "true" if value else "false"
        elif isinstance(value, int):
            text = str(value)
        elif isinstance(value, float):
            # repr() round-trips: the adapter parses exactly the declared value.
            text = repr(value)
        else:
            text = str(value)
        lines.append(f"{key}={text}")
    return "".join(line + "\n" for line in lines)


def uniform_f64_bytes(
    count: int, seed: int, min_value: float, max_value: float
) -> bytes:
    """Generate ``count`` little-endian ``f64`` values in ``[min, max)``.

    The algorithm is normative (protocol section 4): a SplitMix64 state
    advanced once per element, the top 53 bits mapped to a uniform double.
    """

    if count < 1:
        raise SpecError(f"uniform-f64: count must be positive, got {count}")
    if seed < 0:
        raise SpecError(f"uniform-f64: seed must be non-negative, got {seed}")
    if not min_value < max_value:
        raise SpecError(
            f"uniform-f64: params.min must be below params.max "
            f"(got {min_value} and {max_value})"
        )

    payload = bytearray(count * 8)
    pack_into = struct.Struct("<d").pack_into
    span = max_value - min_value
    state = seed & MASK64
    for index in range(count):
        state = (state + GOLDEN_GAMMA) & MASK64
        z = state
        z = ((z ^ (z >> 30)) * MIX_1) & MASK64
        z = ((z ^ (z >> 27)) * MIX_2) & MASK64
        z ^= z >> 31
        unit = (z >> 11) * SCALE_2_POW_MINUS_53
        pack_into(payload, index * 8, min_value + span * unit)
    return bytes(payload)


def _generator_params(workload: Workload) -> tuple[str, int, int, dict[str, Any]]:
    manifest = workload.data["dataset"]
    generator = str(manifest["generator"])
    count = int(manifest["count"])
    seed = int(manifest["seed"])
    params = dict(manifest.get("params", {}))

    if generator not in SUPPORTED_GENERATORS:
        raise SpecError(
            f"{workload.manifest_path}: dataset.generator '{generator}' is not "
            f"implemented by the harness (supported: {', '.join(SUPPORTED_GENERATORS)})"
        )
    assert generator == "uniform-f64"
    for key in ("min", "max"):
        if key not in params:
            raise SpecError(
                f"{workload.manifest_path}: uniform-f64 requires dataset.params.{key}"
            )
        if isinstance(params[key], bool) or not isinstance(params[key], (int, float)):
            raise SpecError(
                f"{workload.manifest_path}: dataset.params.{key} must be a number"
            )
    return generator, count, seed, params


def uniform_f64_payload(generator: str, count: int, seed: int, params: dict[str, Any]) -> bytes:
    if generator != "uniform-f64":
        raise SpecError(f"unsupported dataset generator '{generator}'")
    return uniform_f64_bytes(count, seed, float(params["min"]), float(params["max"]))


def ensure_dataset(
    workload: Workload, data_dir: Path | None = None
) -> Dataset:
    """Generate (or refresh) the workload's dataset and hash it.

    Bytes are never committed: the cache under ``.data/`` is rebuilt from the
    manifest whenever the file is missing, truncated or different.
    """

    generator, count, seed, params = _generator_params(workload)
    payload = uniform_f64_payload(generator, count, seed, params)
    digest = hashlib.sha256(payload).hexdigest()

    params_digest = hashlib.sha256(
        json.dumps(params, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()[:8]
    directory = data_dir if data_dir is not None else REPO_ROOT / ".data"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{workload.name}-{generator}-{count}-{seed}-{params_digest}.bin"

    write_needed = True
    if path.is_file() and path.stat().st_size == len(payload):
        write_needed = hashlib.sha256(path.read_bytes()).hexdigest() != digest
    if write_needed:
        path.write_bytes(payload)

    return Dataset(
        path=path,
        generator=generator,
        count=count,
        seed=seed,
        params=params,
        sha256=digest,
        byte_size=len(payload),
    )
