"""Parity tests for the dataset generators.

A generator's bytes are its contract: the same id must always produce the same
bytes, and the MoonBit core and this Python reference must agree before a hash
becomes a fixture. The hashes below are asserted by `moon test` in
`moonperf/core/dataset/dataset_test.mbt` as well, so a change to either side
fails both suites.
"""

from __future__ import annotations

import hashlib
import struct
import unittest

import reference_generators
from mpf.dataset import uniform_f64_bytes

UNIFORM_GOLDEN = "fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2"
RECORDS_SMALL_HEX = (
    "91000000000000002300000000000000f8000000000000004b00000000000000"
)
RECORDS_GOLDEN = "a0bf64a4d028cc768a1ce138b7b4bf7cd9bd6a57244bd51c5996575682eba13c"
STRINGS_SMALL_HEX = (
    "0400000005000000746f646663030000006c797303000000657979040000006c706273"
    "000000000000000000000000000000000000000002000000"
)
STRINGS_GOLDEN = "76ede39d734ae67e1994654c660d011e57d021d2c3e62be1577496d371116681"
NULLABLE_SMALL_HEX = (
    "0a000000090000000000000005000000000000000800000000000000000000000000000000000000000000"
    "00000000000000000002000000000000000000000000000000010000000000000000000000000000004701"
)
NULLABLE_GOLDEN = "d57afd010d9ac41fb516b2879201971fe1e960c25f6a76afcc31b13de57bda93"
COLUMNAR_SMALL_HEX = (
    "08000000410000000000000013000000000000005a00000000000000"
    "23000000000000003d0000000000000030000000000000002d00000000"
    "0000002100000000000000010000000200000004000000050000000100"
    "0000020000000200000003000000"
)
COLUMNAR_GOLDEN = "e99550ab9f5c8e5d289cdfb90f9ca4303df495a6afc79b106a0b84a5b5361e79"
CSV_SMALL = "id,category,amount\n0,1,19\n1,2,35\n2,1,48\n3,1,33\n4,0,50\n"
CSV_GOLDEN = "d9bad5505aec0b089a00aebd2a7591a7ae2654f9270949917b30f1950d8afeb3"


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


def decode_strings(payload: bytes) -> tuple[list[str], list[int]]:
    """Split a strings payload into its dictionary and its index column."""

    (distinct,) = struct.unpack_from("<I", payload, 0)
    offset = 4
    dictionary = []
    for _ in range(distinct):
        (length,) = struct.unpack_from("<I", payload, offset)
        offset += 4
        dictionary.append(payload[offset : offset + length].decode("ascii"))
        offset += length
    indices = list(struct.unpack_from(f"<{len(payload) - offset >> 2}I", payload, offset))
    return dictionary, indices


class StringsTest(unittest.TestCase):
    def test_small_layout_is_stable(self) -> None:
        payload = reference_generators.strings_bytes(
            **reference_generators.SMALL_STRINGS
        )
        self.assertEqual(payload.hex(), STRINGS_SMALL_HEX)

    def test_golden_hash_matches_the_core(self) -> None:
        payload = reference_generators.strings_bytes(
            **reference_generators.GOLDEN_STRINGS
        )
        self.assertEqual(len(payload), 579_316)
        self.assertEqual(sha256_hex(payload), STRINGS_GOLDEN)

    def test_dictionary_and_indices_are_well_formed(self) -> None:
        payload = reference_generators.strings_bytes(
            count=200, seed=3, distinct=50, value_len_min=2, value_len_max=6, skew=2
        )
        dictionary, indices = decode_strings(payload)
        self.assertEqual(len(dictionary), 50)
        self.assertEqual(len(indices), 200)
        self.assertTrue(all(2 <= len(value) <= 6 for value in dictionary))
        self.assertTrue(all(value.islower() and value.isascii() for value in dictionary))
        self.assertTrue(all(0 <= index < 50 for index in indices))

    def test_skew_concentrates_the_index_column(self) -> None:
        plain = decode_strings(
            reference_generators.strings_bytes(5_000, 9, 100, 4, 4, 1)
        )[1]
        skewed = decode_strings(
            reference_generators.strings_bytes(5_000, 9, 100, 4, 4, 4)
        )[1]
        hot_plain = sum(1 for index in plain if index < 10) / len(plain)
        hot_skewed = sum(1 for index in skewed if index < 10) / len(skewed)
        self.assertGreater(hot_skewed, hot_plain * 2)

    def test_invalid_parameters_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            reference_generators.strings_bytes(4, 1, 0, 4, 8, 1)
        with self.assertRaises(ValueError):
            reference_generators.strings_bytes(4, 1, 10, 8, 4, 1)
        with self.assertRaises(ValueError):
            reference_generators.strings_bytes(4, 1, 10, 4, 8, 0)

def decode_nullable_column(payload: bytes) -> tuple[int, list[tuple[int, bool]]]:
    """Split a nullable-column payload into (row_count, [(value, valid)])."""

    (count,) = struct.unpack_from("<I", payload, 0)
    bitmap_start = 4 + count * 8
    rows = []
    for row in range(count):
        (value,) = struct.unpack_from("<q", payload, 4 + row * 8)
        valid = bool(payload[bitmap_start + row // 8] >> (row % 8) & 1)
        rows.append((value, valid))
    return count, rows


class NullableColumnTest(unittest.TestCase):
    def test_small_layout_is_stable(self) -> None:
        payload = reference_generators.nullable_column_bytes(
            **reference_generators.SMALL_NULLABLE
        )
        self.assertEqual(payload.hex(), NULLABLE_SMALL_HEX)

    def test_golden_hash_matches_the_core(self) -> None:
        payload = reference_generators.nullable_column_bytes(
            **reference_generators.GOLDEN_NULLABLE
        )
        self.assertEqual(len(payload), 812_504)
        self.assertEqual(sha256_hex(payload), NULLABLE_GOLDEN)

    def test_bitmap_and_padding_agree(self) -> None:
        count, rows = decode_nullable_column(
            reference_generators.nullable_column_bytes(1_000, 5, 0, 100, 25)
        )
        self.assertEqual(count, 1_000)
        # 25 % nulls, so roughly three quarters of the bitmap is set; the
        # generator defines the exact column, so assert the invariant instead
        # of a fragile percentage.
        valid = [row for row in rows if row[1]]
        nulls = [row for row in rows if not row[1]]
        self.assertTrue(valid and nulls)
        self.assertTrue(all(0 <= value <= 100 for value, _ in rows))
        self.assertTrue(all(value == 0 for value, _ in nulls))
        self.assertAlmostEqual(len(valid) / count, 0.75, delta=0.05)

    def test_invalid_parameters_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            reference_generators.nullable_column_bytes(4, 1, 10, 0, 10)
        with self.assertRaises(ValueError):
            reference_generators.nullable_column_bytes(4, 1, 0, 10, 101)

def decode_columnar(payload: bytes) -> tuple[list[int], list[int]]:
    """Split a columnar-gather payload into its value column and index vector."""

    (count,) = struct.unpack_from("<I", payload, 0)
    values = list(struct.unpack_from(f"<{count}q", payload, 4))
    indices = list(struct.unpack_from(f"<{count}I", payload, 4 + count * 8))
    return values, indices


class ColumnarGatherTest(unittest.TestCase):
    def test_small_layout_is_stable(self) -> None:
        payload = reference_generators.columnar_gather_bytes(
            **reference_generators.SMALL_COLUMNAR
        )
        self.assertEqual(payload.hex(), COLUMNAR_SMALL_HEX)

    def test_golden_hash_matches_the_core(self) -> None:
        payload = reference_generators.columnar_gather_bytes(
            **reference_generators.GOLDEN_COLUMNAR
        )
        self.assertEqual(len(payload), 12_000_004)
        self.assertEqual(sha256_hex(payload), COLUMNAR_GOLDEN)

    def test_indices_are_in_range_and_local(self) -> None:
        for locality in (1, 8):
            payload = reference_generators.columnar_gather_bytes(
                4_000, 7, 0, 1_000, locality
            )
            values, indices = decode_columnar(payload)
            self.assertEqual(len(values), 4_000)
            self.assertEqual(len(indices), 4_000)
            self.assertTrue(all(0 <= index < 4_000 for index in indices))
            # A run of `locality` rows walks forward one index at a time.
            starts = range(0, 4_000, locality)
            for start in starts:
                run = indices[start : start + locality]
                self.assertEqual(run, list(range(run[0], run[0] + len(run))))

    def test_locality_one_is_not_sequential(self) -> None:
        payload = reference_generators.columnar_gather_bytes(
            1_000, 11, 0, 1_000, 1
        )
        _, indices = decode_columnar(payload)
        self.assertNotEqual(indices, sorted(indices))

    def test_invalid_parameters_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            reference_generators.columnar_gather_bytes(4, 1, 10, 0, 1)
        with self.assertRaises(ValueError):
            reference_generators.columnar_gather_bytes(4, 1, 0, 10, 0)

class CsvRecordsTest(unittest.TestCase):
    def test_small_text_is_stable(self) -> None:
        payload = reference_generators.csv_records_bytes(
            **reference_generators.SMALL_CSV
        )
        self.assertEqual(payload.decode("ascii"), CSV_SMALL)

    def test_golden_hash_matches_the_core(self) -> None:
        payload = reference_generators.csv_records_bytes(
            **reference_generators.GOLDEN_CSV
        )
        self.assertEqual(len(payload), 1_515_076)
        self.assertEqual(sha256_hex(payload), CSV_GOLDEN)

    def test_every_row_has_three_integer_fields(self) -> None:
        payload = reference_generators.csv_records_bytes(
            500, 3, categories=8, amount_max=1000
        ).decode("ascii")
        lines = payload.splitlines()
        self.assertEqual(lines[0], "id,category,amount")
        for row, line in enumerate(lines[1:]):
            fields = line.split(",")
            self.assertEqual(len(fields), 3)
            self.assertEqual(int(fields[0]), row)
            self.assertTrue(0 <= int(fields[1]) < 8)
            self.assertTrue(0 <= int(fields[2]) <= 1000)

    def test_invalid_parameters_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            reference_generators.csv_records_bytes(4, 1, 0, 10)
        with self.assertRaises(ValueError):
            reference_generators.csv_records_bytes(4, 1, 4, 0)
