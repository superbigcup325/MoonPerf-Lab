"""Parity tests for the dataset generators.

A generator's bytes are its contract: the same id must always produce the same
bytes, and the MoonBit core and this Python reference must agree before a hash
becomes a fixture. The hashes below are asserted by `moon test` in
`moonperf/core/dataset/dataset_test.mbt` as well, so a change to either side
fails both suites.
"""

from __future__ import annotations

import hashlib
import unittest

import reference_generators
from mpf.dataset import uniform_f64_bytes

UNIFORM_GOLDEN = "fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2"
RECORDS_SMALL_HEX = (
    "91000000000000002300000000000000f8000000000000004b00000000000000"
)
RECORDS_GOLDEN = "a0bf64a4d028cc768a1ce138b7b4bf7cd9bd6a57244bd51c5996575682eba13c"


def sha256_hex(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


class UniformF64Test(unittest.TestCase):
    def test_oracle_matches_the_committed_golden_hash(self) -> None:
        payload = uniform_f64_bytes(1_000_000, 20261020, -1.0, 1.0)
        self.assertEqual(sha256_hex(payload), UNIFORM_GOLDEN)
        self.assertEqual(len(payload), 8_000_000)


class StructuredRecordsTest(unittest.TestCase):
    def test_small_layout_is_stable(self) -> None:
        payload = reference_generators.structured_records_bytes(
            **reference_generators.SMALL_RECORDS
        )
        self.assertEqual(len(payload), 2 * 16)
        self.assertEqual(payload.hex(), RECORDS_SMALL_HEX)

    def test_golden_hash_matches_the_core(self) -> None:
        payload = reference_generators.structured_records_bytes(
            **reference_generators.GOLDEN_RECORDS
        )
        self.assertEqual(len(payload), 16_000_000)
        self.assertEqual(sha256_hex(payload), RECORDS_GOLDEN)

    def test_key_and_payload_ranges_are_respected(self) -> None:
        payload = reference_generators.structured_records_bytes(
            count=1000, seed=7, key_bits=10, payload_min=5, payload_max=9
        )
        for index in range(1000):
            key = int.from_bytes(payload[index * 16 : index * 16 + 8], "little")
            value = int.from_bytes(payload[index * 16 + 8 : index * 16 + 16], "little")
            self.assertLess(key, 1 << 10)
            self.assertGreaterEqual(value, 5)
            self.assertLessEqual(value, 9)

    def test_invalid_parameters_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            reference_generators.structured_records_bytes(4, 1, 0, 0, 100)
        with self.assertRaises(ValueError):
            reference_generators.structured_records_bytes(4, 1, 8, 100, 0)
        with self.assertRaises(ValueError):
            reference_generators.structured_records_bytes(4, 1, 8, -1, 100)

    def test_records_are_byte_identical_to_the_spec_example(self) -> None:
        """The first record of the golden set, byte for byte.

        Key 0x0b66e6 = 747 238 with key_bits = 20, payload 0x0cba74 = 834 164;
        the values come from the documented SplitMix64 stream and pin the
        little-endian layout independently of the whole-file hash.
        """
        payload = reference_generators.structured_records_bytes(
            **reference_generators.GOLDEN_RECORDS
        )
        self.assertEqual(
            payload[:16].hex(), "e6680b000000000074ba0c0000000000"
        )


if __name__ == "__main__":
    unittest.main()
