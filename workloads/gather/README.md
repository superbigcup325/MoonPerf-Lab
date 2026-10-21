# gather

**Tier:** component · **Status:** active (v1)

## Research question

Copy a million values through an index vector into an output vector: one
indirect read and one sequential write per row. What does that cost in MoonBit
compared with Rust and C, and how much of it is the indirection itself?

`numeric-scan` measures a contiguous pass and `hash-join` measures a
data-dependent walk; this workload sits between them. The index column is
generated in runs, so the same kernel covers "random" and "mostly sequential"
access without a second workload — a one-parameter locality axis.

## Dataset

`columnar-gather` with `count = 4_000_000`, seed `20261025`, values in
`[0, 1_000_000]` and `locality = 16` (48 000 004 bytes: `u32` row count, then
`count` × `i64` value, then `count` × `u32` index). The artifact records the
dataset SHA-256.

Four million rows, not one: at 1 000 000 rows one pass is about 1.5 ms, so a
whole process is 300–400 ms and the harness's per-process overhead is a
measurable share of every sample — on this host that produced 5–15 % CV no
matter how many inner repeats were used. At 4 000 000 rows one pass is about
5 ms, a 40-repeat sample is about 0.4 s of kernel, and a direct probe measured
0.7–2.2 % CV. The size is part of the experiment, not a knob to tune per run.

Indices are generated in runs of 16: each run draws a random start and walks
forward, so a quarter of the accesses are sequential runs and the rest are
random starts. Every index is in `[0, count)` by construction and the adapter
materializes the index column without a per-row range check — the question is
the gather loop, not the cost of an error path. A workload that wants the
bounds-check cost is a separate implementation id.

## Output and correctness

| Field | Type | Meaning |
| --- | --- | --- |
| `rows` | integer | gathered rows |
| `checksum` | string | 16 lowercase hex digits |

The kernel gathers into a per-pass output vector and checksums the result with
a position weight, so the checksum is sensitive to a skipped row, a permuted
row and a wrong index, not just to the set of values it happened to touch:

```
for row in 0..rows:  out[row] = values[index[row]]
checksum = sum(out[row] * (row + 1) for every row) mod 2^64
```

Verification is `exact` against the Rust reference. The output vector is
allocated and zeroed once, before the timed loop, and reused for every pass:
that is what a real operator does with a batch buffer, and allocating 8 MB per
pass would measure the allocator and page faults instead of the gather (a first
attempt did exactly that and came out `unstable` with CV 5–8 %).

Fault injection is recorded, not promised. Two injected faults on the C
adapter:

| Fault | `checksum` | Verdict |
| --- | --- | --- |
| none (correct) | `0377c6e146371627` | passes |
| index off by one, wrapped into range | `03780ed9b1c95b23` | fails |
| position weight dropped from the checksum | `000000744f4b6744` | fails |

## Implementations

| id | Language | Shape | State |
| --- | --- | --- | --- |
| `rust` | Rust | `Vec<u64>` values and `Vec<u32>` indices; gather into a per-pass `Vec<u64>` with unchecked reads; `black_box` across repeats | Reference |
| `moonbit` | MoonBit | `Array[UInt64]` values and `Array[Int]` indices; same output vector; `Bench::keep` across repeats | Timed |
| `c` | C17 | `uint64_t`/`uint32_t` arrays; same output vector; empty-asm barrier across repeats | Timed |

### Fairness constraints

- All implementations parse the same header and materialize the same two
  arrays before the timed loop: 8-byte values, 4-byte indices, no per-row
  object and no widened index type.
- The output vector is allocated once per process, before the timed loop, and
  written sequentially by every pass; the checksum reads it back sequentially.
  Allocation and zeroing are setup, not kernel.
- No per-row bounds check in any implementation; the generator guarantees the
  indices. Adding one is a different implementation id.
- The kernel must not be hoisted: `black_box` / `Bench::keep` / empty-asm
  barrier, and the `K = 10 -> 20` slope stays near linear.
- A different locality or value range is a dataset change: bump the workload
  version, do not edit v1.

## Measurement notes

The manifest uses `warmup = 3`, `repeats = 20`, `timeout_s = 120`,
`inner_repeats = 40` and `max_cv = 0.05`. One pass is about 5 ms on the recorded
host, so a sample is about 0.4 s of kernel and the 48 MB dataset load stays
under the 0.10 component setup gate.

The artifact of record is
`results/gather/20261021T140344Z-b6d5f9215963.json`: clean tree, `verdict=ok`,
dataset SHA-256 `34c20a7b73739ef4941a20ca1a56153e54b93e82445c267c3e4d96607956cbdc`.

| Implementation | Median ns/iter | CV | Setup fraction |
| --- | ---: | ---: | ---: |
| `c` | 10 109 469.5 | 2.05 % | 5.25 % |
| `rust` | 8 314 058.5 | 3.24 % | 5.68 % |
| `moonbit` | 16 577 759 | 2.49 % | 3.69 % |

`K=10 -> 20` slope ratios are 0.89 / 0.99 / 1.01. The gather is the first
workload where MoonBit is about 2× the Rust median on a loop with no arithmetic
to blame: 4 M dependent loads per pass, so the difference is in the generated
load path or the layout of the two arrays, not in the operation mix. That is an
attribution question (P4), not a conclusion this artifact can carry.

**Admission note.** The 1 000 000-row version of this workload could not be
admitted: clean-tree runs swung between CV 3 % and 15 % as background load
changed, at 200 and at 800 inner repeats, and a cache-resident 250 000-row
variant showed the same bursty spread, while the compute-bound `numeric-scan`
kernel held CV 2 % in the same sessions. The protocol does not allow relaxing
`max_cv`, so the size was changed instead — at 4 M rows the kernel is about
5 ms per pass and dominates the sample. A rerun on a busy host may still be
recorded as `unstable`; that is the host, not the workload.
