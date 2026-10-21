# hash-join

**Tier:** component · **Status:** active (v1)

## Research question

Build a hash table over one half of a record stream, probe it with the other
half, and count the matching pairs. Where does the difference between MoonBit
and Rust come from: the hash itself, the chain walk, the table layout, or the
memory traffic that the probe side causes?

This is the first `component` workload: unlike `numeric-scan`, the kernel owns
a data structure, touches memory in a data-dependent order and allocates. Those
are the parts a micro kernel cannot see.

## Dataset

`structured-records` with `count = 1_000_000`, seed `20261024`, `key_bits = 20`
and payloads in `[0, 1_000_000]` (16 MB, 16-byte records: little-endian `u64`
key, then `u64` payload). The expected SHA-256 is
`a413e1deb6d87790988d4331fcc264d4d12047c1b0f789134796812ccb0aa23d`.

**The split is by position, not by a header:** the first half of the records is
the build side, the second half is the probe side. With `count = 1_000_000`
that is 500 000 build rows and 500 000 probe rows. An adapter must reject an
odd record count or a file size that is not a multiple of 16.

The generator draws keys uniformly from `[0, 2^20)`, so the build side covers
about half of the key space and a probe row matches with probability
`1 - e^-0.5 ≈ 39 %`. Duplicate keys occur in both halves by construction: a
build key can repeat, and two probe rows can share a key. The join is therefore
many-to-many and must count every matching (build, probe) pair.

## Output and correctness

Implementations write a JSON object with four fields through the adapter
contract:

| Field | Type | Meaning |
| --- | --- | --- |
| `build_rows` | integer | records in the build half (`count / 2`) |
| `probe_rows` | integer | records in the probe half |
| `pairs` | integer | matching (build, probe) pairs, duplicates included |
| `checksum` | string | 16 lowercase hex digits |

`checksum` is the wrapping `u64` sum of `build_payload + probe_payload` over
every matching pair:

```
checksum = sum(build.payload + probe.payload for every matching pair) mod 2^64
```

It is a pure function of the data — addition is commutative and the wrapping
sum does not care in which order the pairs are visited. A chained table, an
open-addressing table and a sort-merge join all produce the same checksum, so
the gate compares the answer rather than the algorithm. It is printed as 16
hex digits (leading zeros included) so the JSON value is exact: a 64-bit
integer would not survive a JSON number.

Verification is `exact` against the Rust reference: the integers and the
checksum string must match exactly.

Fault injection is recorded, not promised. Two injected faults on the C
adapter:

| Fault | `pairs` | `checksum` | Verdict |
| --- | ---: | --- | --- |
| none (correct) | 238 491 | `00000037817646df` | passes |
| checksum drops the build payload | 238 491 | `0000001bc4a8bc0f` | fails on `checksum` |
| every 1000th build row dropped | 238 265 | `0000003773b7016d` | fails on `pairs` and `checksum` |

The first fault is the dangerous one: the counters are right and only the
accumulation is wrong, so a gate that compared only `pairs` would let it
through. A third attempt — skipping only the last build row — changed nothing
on this dataset because that key has no probe match, which is exactly why the
gate is not allowed to rest on one example.

## Implementations

| id | Language | Shape | State |
| --- | --- | --- | --- |
| `rust` | Rust | records materialized as one `Vec<u64>`; chained table (multiply-shift hash, load factor ≤ 0.5); `black_box` across repeats | Reference; runs and is timed |
| `moonbit` | MoonBit | same table shape over an `Array[UInt64]`; `Bench::keep` across repeats | P2.2 |
| `c` | C17 | same table shape over a `uint64_t` array; empty-asm barrier across repeats | P2.2 |

### Fairness constraints

- All implementations materialize the input the same way: the raw 16-byte
  records read as little-endian `u64` words, one flat array, no per-row object.
  The build/probe split happens on the array, not by re-reading the file.
- All implementations use the same table strategy: a chained table with a
  multiply-shift hash and a load factor of at most 0.5. A different strategy is
  a different implementation id, not a hidden optimization.
- The table and the chain array are allocated inside the timed kernel, once per
  kernel pass, not reused across the `K` repeats. Reusing them would measure a
  different (cheaper) kernel.
- The kernel must not be hoisted: use `black_box` / `Bench::keep` on the result
  and keep the `K = 10 -> 20` slope near linear.
- `checksum` is printed with leading zeros; `pairs`, `build_rows` and
  `probe_rows` are JSON integers.

## Measurement notes

The manifest uses `warmup = 3`, `repeats = 20`, `timeout_s = 120`,
`inner_repeats = 20` and `max_cv = 0.05`. One kernel pass is about 22 ms on the
recorded host, so a sample is about 0.44 s and the dataset load (16 MB plus
the word split) is a small fraction of it. This is a `component` workload, so
the setup gate is `setup_fraction <= 0.10`.

## What would falsify the experiment

- The checksum stops being a pure function of the data (an implementation that
  accumulates in a different order and gets a different answer).
- The implementations read the split differently (one treats the probe half as
  the build side).
- A skipped record, a dropped duplicate or an ignored chain entry passes the
  gate.
- The table is reused across repeats, so `K` measures one allocation instead of
  `K` joins.
- The timeout leaves an orphan process that runs during the next sample.
