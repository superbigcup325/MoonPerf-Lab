# gather

**Tier:** component · **Status:** draft (v1; implemented and fault-injected, artifact pending a quiet host)

## Research question

Copy a million values through an index vector into an output vector: one
indirect read and one sequential write per row. What does that cost in MoonBit
compared with Rust and C, and how much of it is the indirection itself?

`numeric-scan` measures a contiguous pass and `hash-join` measures a
data-dependent walk; this workload sits between them. The index column is
generated in runs, so the same kernel covers "random" and "mostly sequential"
access without a second workload — a one-parameter locality axis.

## Dataset

`columnar-gather` with `count = 1_000_000`, seed `20261025`, values in
`[0, 1_000_000]` and `locality = 16` (12 000 004 bytes: `u32` row count, then
`count` × `i64` value, then `count` × `u32` index). The expected SHA-256 is
`e99550ab9f5c8e5d289cdfb90f9ca4303df495a6afc79b106a0b84a5b5361e79`.

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
`inner_repeats = 80` and `max_cv = 0.05`. One pass is about 2.4 ms on the
recorded host, so a sample is about 0.2 s and the dataset load (12 MB plus the
column materialization) stays small relative to it. This is a `component`
workload: the setup gate is `setup_fraction <= 0.10`.

**No artifact yet — the host is the blocker, not the workload.** Four
clean-tree runs on 2026-10-21 all came out `unstable`, with the CV rising as the
machine got busier:

| Attempt | CV (C / Rust / MoonBit) |
| --- | --- |
| first (output vector allocated per pass) | 5.1 / 8.3 / 7.4 % |
| output buffer reused | 10.0 / 14.5 / 10.4 % |
| retry | — / — / 15.6 % |
| retry | — / 21.6 / 22.0 % |

A compute-bound kernel measured on the same host minutes earlier held CV 2.0 %,
so this is not a general timing problem: the gather working set is 24 MB
(values 8 MB + indices 4 MB + output 8 MB) and exceeds this CPU's cache, which
makes it sensitive to the memory traffic of whatever else shares the machine. A
cache-resident 250 000-row probe was no better (10.9 % CV) while the co-tenant
held the cache.

The protocol does not allow relaxing `max_cv`, so the workload stays `draft`
until a run of this shape is stable. Options, in order of preference: measure
on a quiet or dedicated host; or decide deliberately that this workload
measures a memory-bandwidth-bound path and record the smaller cache-resident
size as a separate version/manifest. Both are decisions for the roadmap, not
for this file.

## What would falsify the experiment

- An implementation gathers in a different order or into a reused buffer, so
  the checksum matches while the kernel measured is different.
- An index fault (off by one, dropped row, drop-the-weight checksum) passes the
  gate.
- The implementations disagree on the record layout or the header.
- The timeout leaves an orphan process that runs during the next sample.
