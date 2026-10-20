"""Dataset generation: the bytes are normative, so they are pinned."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from mpf.dataset import (
    render_params,
    uniform_f64_bytes,
    ensure_dataset,
)
from mpf.specs import SpecError, load_workload

MANIFEST = """\
schema_version = 1
name = "unit-scan"
version = 1
status = "draft"
tier = "micro"
summary = "dataset generation fixture"

[dataset]
generator = "uniform-f64"
count = 4
seed = 0

[dataset.params]
min = -1.0
max = 1.0

[verify]
mode = "exact"
fields = ["n"]

[measurement]
warmup = 0
repeats = 1
timeout_s = 5
inner_repeats = 1
"""


def _reference_bytes(count: int, seed: int, low: float, high: float) -> bytes:
    """An independent transcription of protocol section 4."""

    import struct

    mask = (1 << 64) - 1
    state = seed & mask
    span = high - low
    chunks = []
    for _ in range(count):
        state = (state + 0x9E3779B97F4A7C15) & mask
        z = state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & mask
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & mask
        z ^= z >> 31
        unit = (z >> 11) * 2.0**-53
        chunks.append(struct.pack("<d", low + span * unit))
    return b"".join(chunks)


class UniformF64Test(unittest.TestCase):
    def test_matches_pinned_bytes(self) -> None:
        payload = uniform_f64_bytes(4, 0, -1.0, 1.0)
        self.assertEqual(
            payload.hex(),
            "72c75e0e2a88e83fa0465e956187c1bfb0fddfb9e84eeebf20931c2aee22ee3f",
        )
        self.assertEqual(
            hashlib.sha256(payload).hexdigest(),
            "d0cf36fc50b41960226456be91ce739cb29f38015ab0f2af3842699f2b8763e7",
        )

    def test_matches_independent_transcription(self) -> None:
        for count, seed, low, high in ((1, 1, 0.0, 1.0), (257, 20261020, -1.0, 1.0)):
            with self.subTest(count=count, seed=seed):
                self.assertEqual(
                    uniform_f64_bytes(count, seed, low, high),
                    _reference_bytes(count, seed, low, high),
                )

    def test_known_digest_for_the_workload_dataset(self) -> None:
        payload = uniform_f64_bytes(1000, 42, -1.0, 1.0)
        self.assertEqual(
            hashlib.sha256(payload).hexdigest(),
            "08af9192973b7972f8b053ff1ddee063725fd4d80115449355c483f3005a0933",
        )

    def test_values_stay_in_range(self) -> None:
        import struct

        payload = uniform_f64_bytes(64, 7, -2.0, 3.0)
        values = struct.unpack(f"<{len(payload) // 8}d", payload)
        self.assertTrue(all(-2.0 <= value < 3.0 for value in values))

    def test_rejects_invalid_parameters(self) -> None:
        with self.assertRaises(SpecError):
            uniform_f64_bytes(0, 0, 0.0, 1.0)
        with self.assertRaises(SpecError):
            uniform_f64_bytes(4, 0, 1.0, 1.0)
        with self.assertRaises(SpecError):
            uniform_f64_bytes(4, -1, 0.0, 1.0)

    def test_is_deterministic(self) -> None:
        self.assertEqual(
            uniform_f64_bytes(32, 9, -1.0, 1.0),
            uniform_f64_bytes(32, 9, -1.0, 1.0),
        )


class ParamsFileTest(unittest.TestCase):
    def test_sorted_key_value_lines(self) -> None:
        text = render_params({"threshold": 0.5, "count": 3, "flag": True, "name": "x"})
        self.assertEqual(text, "count=3\nflag=true\nname=x\nthreshold=0.5\n")

    def test_empty_params_render_as_empty_file(self) -> None:
        self.assertEqual(render_params({}), "")


class EnsureDatasetTest(unittest.TestCase):
    def test_writes_the_file_and_reports_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workload_dir = root / "unit-scan"
            workload_dir.mkdir()
            (workload_dir / "workload.toml").write_text(MANIFEST, encoding="utf-8")
            workload = load_workload(workload_dir / "workload.toml")

            dataset = ensure_dataset(workload, data_dir=root / ".data")
            self.assertEqual(dataset.count, 4)
            self.assertEqual(dataset.byte_size, 32)
            self.assertEqual(dataset.sha256, hashlib.sha256(dataset.path.read_bytes()).hexdigest())
            self.assertEqual(dataset.path.read_bytes(), uniform_f64_bytes(4, 0, -1.0, 1.0))

            again = ensure_dataset(workload, data_dir=root / ".data")
            self.assertEqual(again.path, dataset.path)
            self.assertEqual(again.sha256, dataset.sha256)


if __name__ == "__main__":
    unittest.main()
