"""Independent reference for the dataset generators the core implements.

These functions exist only to cross-check the MoonBit core: the golden hashes in
this module are asserted by both `tests/test_generators.py` here and by
`moon test` in the core. They are deliberately written from the protocol text,
not imported from `mpf.dataset`, so two implementations have to agree before a
hash becomes a fixture.
"""

from __future__ import annotations

import struct

MASK64 = (1 << 64) - 1
GOLDEN = 0x9E3779B97F4A7C15


def mix64(state: int) -> int:
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
    return z ^ (z >> 31)


def structured_records_bytes(
    count: int, seed: int, key_bits: int, payload_min: int, payload_max: int
) -> bytes:
    """Fixed 16-byte records: little-endian u64 key, then u64 payload."""

    if count < 1:
        raise ValueError("count must be positive")
    if seed < 0:
        raise ValueError("seed must be non-negative")
    if not 1 <= key_bits <= 64:
        raise ValueError("key_bits must be between 1 and 64")
    if payload_min < 0 or payload_max < payload_min:
        raise ValueError("payload range is invalid")
    span = payload_max - payload_min + 1
    shift = 64 - key_bits
    out = bytearray(count * 16)
    state = seed & MASK64
    pack_into = struct.Struct("<QQ").pack_into
    for index in range(count):
        state = (state + GOLDEN) & MASK64
        key_z = mix64(state)
        state = (state + GOLDEN) & MASK64
        payload_z = mix64(state)
        key = key_z if key_bits == 64 else key_z >> shift
        payload = payload_min + payload_z % span
        pack_into(out, index * 16, key, payload)
    return bytes(out)


SMALL_RECORDS = dict(count=2, seed=1, key_bits=8, payload_min=0, payload_max=100)
GOLDEN_RECORDS = dict(
    count=1_000_000, seed=20261021, key_bits=20, payload_min=0, payload_max=1_000_000
)


def strings_bytes(
    count: int,
    seed: int,
    distinct: int,
    value_len_min: int,
    value_len_max: int,
    skew: int,
) -> bytes:
    """Dictionary-encoded string column: dictionary, then row indices."""

    if count < 1:
        raise ValueError("count must be positive")
    if seed < 0:
        raise ValueError("seed must be non-negative")
    if not 1 <= distinct <= 1_000_000:
        raise ValueError("distinct must be between 1 and 1000000")
    if not 1 <= value_len_min <= value_len_max <= 255:
        raise ValueError("value length range is invalid")
    if not 1 <= skew <= 8:
        raise ValueError("skew must be between 1 and 8")
    out = bytearray(struct.pack("<I", distinct))
    span = value_len_max - value_len_min + 1
    state = seed & MASK64
    for _ in range(distinct):
        state = (state + GOLDEN) & MASK64
        length = value_len_min + mix64(state) % span
        out += struct.pack("<I", length)
        for _ in range(length):
            state = (state + GOLDEN) & MASK64
            out.append(ord("a") + mix64(state) % 26)
    for _ in range(count):
        state = (state + GOLDEN) & MASK64
        z = mix64(state)
        for _ in range(1, skew):
            state = (state + GOLDEN) & MASK64
            candidate = mix64(state)
            if candidate < z:
                z = candidate
        out += struct.pack("<I", ((z >> 32) * distinct) >> 32)
    return bytes(out)


SMALL_STRINGS = dict(
    count=6, seed=1, distinct=4, value_len_min=3, value_len_max=5, skew=2
)
GOLDEN_STRINGS = dict(
    count=100_000, seed=20261022, distinct=10_000,
    value_len_min=4, value_len_max=24, skew=3,
)


def nullable_column_bytes(
    count: int, seed: int, value_min: int, value_max: int, null_percent: int
) -> bytes:
    """Integer column with a validity bitmap: values first, then the bitmap."""

    if count < 1:
        raise ValueError("count must be positive")
    if seed < 0:
        raise ValueError("seed must be non-negative")
    if value_min < 0 or value_max < value_min:
        raise ValueError("value range is invalid")
    if not 0 <= null_percent <= 100:
        raise ValueError("null_percent must be between 0 and 100")
    span = value_max - value_min + 1
    bitmap_bytes = (count + 7) // 8
    out = bytearray(4 + count * 8 + bitmap_bytes)
    struct.pack_into("<I", out, 0, count)
    state = seed & MASK64
    for row in range(count):
        state = (state + GOLDEN) & MASK64
        valid = mix64(state) % 100 >= null_percent
        state = (state + GOLDEN) & MASK64
        value = value_min + mix64(state) % span if valid else 0
        struct.pack_into("<q", out, 4 + row * 8, value)
        if valid:
            out[4 + count * 8 + row // 8] |= 1 << (row % 8)
    return bytes(out)


SMALL_NULLABLE = dict(count=10, seed=1, value_min=0, value_max=9, null_percent=50)
GOLDEN_NULLABLE = dict(
    count=100_000, seed=20261023, value_min=0, value_max=1_000_000, null_percent=10
)


def columnar_gather_bytes(
    count: int, seed: int, value_min: int, value_max: int, locality: int
) -> bytes:
    """Dense value column plus an index vector gathered in runs of `locality`."""

    if count < 1:
        raise ValueError("count must be positive")
    if seed < 0:
        raise ValueError("seed must be non-negative")
    if value_min < 0 or value_max < value_min:
        raise ValueError("value range is invalid")
    if not 1 <= locality <= 4096:
        raise ValueError("locality must be between 1 and 4096")
    span = value_max - value_min + 1
    out = bytearray(4 + count * 8 + count * 4)
    struct.pack_into("<I", out, 0, count)
    values_start = 4
    state = seed & MASK64
    for row in range(count):
        state = (state + GOLDEN) & MASK64
        struct.pack_into("<q", out, values_start + row * 8, value_min + mix64(state) % span)
    indices_start = values_start + count * 8
    run_start = 0
    while run_start < count:
        run_len = min(locality, count - run_start)
        state = (state + GOLDEN) & MASK64
        base = mix64(state) % (count - run_len + 1)
        for offset in range(run_len):
            struct.pack_into(
                "<I", out, indices_start + (run_start + offset) * 4, base + offset
            )
        run_start += run_len
    return bytes(out)


SMALL_COLUMNAR = dict(
    count=8, seed=1, value_min=0, value_max=99, locality=2
)
GOLDEN_COLUMNAR = dict(
    count=1_000_000, seed=20261025, value_min=0, value_max=1_000_000, locality=16
)


def csv_records_bytes(
    count: int, seed: int, categories: int, amount_max: int
) -> bytes:
    """Deterministic text table: header plus id,category,amount rows."""

    if count < 1:
        raise ValueError("count must be positive")
    if seed < 0:
        raise ValueError("seed must be non-negative")
    if not 1 <= categories <= 4096:
        raise ValueError("categories must be between 1 and 4096")
    if amount_max < 1:
        raise ValueError("amount_max must be positive")
    out = bytearray(b"id,category,amount\n")
    state = seed & MASK64
    category_span = categories
    amount_span = amount_max + 1
    for row in range(count):
        state = (state + GOLDEN) & MASK64
        category = mix64(state) % category_span
        state = (state + GOLDEN) & MASK64
        amount = mix64(state) % amount_span
        out += f"{row},{category},{amount}\n".encode("ascii")
    return bytes(out)


SMALL_CSV = dict(count=5, seed=1, categories=4, amount_max=99)
GOLDEN_CSV = dict(count=100_000, seed=20261026, categories=16, amount_max=1_000_000)
