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
