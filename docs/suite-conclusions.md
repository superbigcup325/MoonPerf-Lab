# What the suite can and cannot conclude

Four active workloads, one protocol, one host. This page is the written answer
to two questions the phase plan asks for: what these measurements support, and
which workload should be measured next.

Nothing here is a score. Each line is one workload on one machine with the
environment attached; the artifacts under `results/` are the evidence, and this
page only summarizes them.

## The suite at a glance

All numbers below come from the committed artifacts, measured by the accepted
harness on the recorded host (12th Gen Intel Core i5-12500H, 16 logical CPUs,
`powersave` governor, 16 GB RAM, CachyOS, x86_64). Medians are ns per
iteration; CV is the coefficient of variation over 20 repeats.

| Workload | Tier | Question | Recorded dataset | Artifact |
| --- | --- | --- | --- | --- |
| [`numeric-scan`](../workloads/numeric-scan/) | micro | cost of a dense `f64` stream through five reductions | `uniform-f64`, 1 000 000, 8 000 000 B | `20261021T055715Z-a47130edbf4b` |
| [`hash-join`](../workloads/hash-join/) | component | build and probe a hash table over 1 M records | `structured-records`, 1 000 000, 16 000 000 B | `20261021T114656Z-b0ff09ba5b87` |
| [`gather`](../workloads/gather/) | component | dependent random loads through an index vector | `columnar-gather`, 4 000 000, 48 000 004 B | `20261021T140344Z-b6d5f9215963` |
| [`sql-groupby`](../workloads/sql-groupby/) | end-to-end | CSV parse plus one fixed `GROUP BY`, hand-written and through an engine | `csv-records`, 2 000 000, 33 415 933 B | `20261021T144852Z-58eace17a9f4` |

| Workload | C17 | Rust | MoonBit | Moonlake 0.3.1 | CV (max) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `numeric-scan` | 1 058 107 | 1 042 542.5 | 2 228 174 | — | 3.99 % |
| `hash-join` | 22 005 496 | 24 314 815 | 24 718 417 | — | 4.16 % |
| `gather` | 10 109 469.5 | 8 314 058.5 | 16 577 759 | — | 3.24 % |
| `sql-groupby` | 26 532 583 | 27 338 584.5 | 29 139 280 | 160 946 952 | 3.91 % |

Every run is `ok`: every implementation passed correctness against the Rust
reference, every CV is under the 5 % gate, every setup fraction is under 10 %,
and every K=10→20 slope is between 0.89 and 1.14 (the kernel really ran).

## What it can conclude

1. **A compute-bound stream is where MoonBit native is furthest from Rust.**
   `numeric-scan` puts MoonBit at 2.14× the Rust median while C sits within
   1.5 %. Five f64 reductions over 8 MB, no allocation, no branching surprises:
   what is left is code generation, and that gap is stable across runs
   (CV 1.9–4.0 %).
2. **A cache-resident hash join is not the same story.** `hash-join` puts
   MoonBit within 1.7 % of Rust, and C 9.5 % ahead. Once the cost is hash
   arithmetic, misses and memory traffic over a 16 MB record stream, the
   codegen gap stops dominating.
3. **Dependent random loads are latency, not arithmetic.** `gather` has MoonBit
   at 1.99× Rust and C at 1.22×. More independent work per element does not help
   a pointer chase; the ordering here is stable (CV 2.0–3.2 %).
4. **An end-to-end path is dominated by parsing, not by the kernel.**
   `sql-groupby` puts hand-written MoonBit at 1.07× Rust and C 2.9 % ahead: the
   same relative ordering as `hash-join`, not as `numeric-scan`.
5. **An engine path is a different measurement.** Moonlake executes the same
   SQL over the same bytes at 5.9× the Rust median, with the parse/plan/scan
   path inside the timed region. That number is a statement about an engine,
   not about a language, and the workload README keeps the two apart.
6. **The harness behaves the same way on every tier.** Same setup semantics
   (baseline recorded, not subtracted), same round-robin order, same gates.
   The suite's own reproducibility — CV ≤ 4.16 %, slopes near 1 — is part of
   what these four artifacts claim.

The interesting result is the disagreement between rows: the ranking flips
between `numeric-scan` and `hash-join`. That disagreement is the finding, and it
is exactly what a summed score would destroy.

## What it cannot conclude

- **Anything ranked.** No aggregate, no leaderboard, no "language X is N % of
  Y". C is 9.5 % faster than Rust on `hash-join`, 2.9 % on `sql-groupby` and
  1.5 % slower on `numeric-scan`; one number cannot carry that.
- **Anything beyond this host and toolchain.** One CPU model, one governor, one
  Linux release, one set of compiler versions (recorded per implementation in
  each artifact). A different machine is a different experiment.
- **Anything about scaling or complexity.** The K=10→20 slope validates that the
  kernel ran `K` times; it is not a complexity measurement and not a growth
  curve.
- **Anything about allocation, concurrency or I/O.** Every workload here is
  single-threaded; each adapter materializes its buffers during setup and the
  kernel works on them, so allocation is present in the program but is not the
  subject of any measurement. Process startup is excluded by construction, and
  no workload reads from a network or a device.
- **Statistical significance.** `max_cv` says a run was stable, not that a 1.7 %
  difference is real. A minimum detectable effect needs repeated baseline runs
  and is P3 work.
- **Transfer to a real application.** These are isolated kernels and one fixed
  query over generated data, not a profile of a program.
- **Anything about the shapes not measured.** The recorded configuration of each
  workload is one point in its declared input matrix (protocol §4); the other
  entries are declarations, not results. `gather` at `locality = 1` or
  `sql-groupby` with 4096 groups is a run away, not a claim away.

## Which workload should I measure next?

A candidate earns a place in the suite by closing a gap the current four cannot
close — not by being easy to write. Ranked:

1. **`text-build` (micro): allocation and string growth.** No workload here is
   *about* allocation. Building a per-row string from parsed fields and
   checksumming it puts the allocator, buffer growth and copies inside the timed
   region — the largest unmeasured part of the MoonBit-first claim. Reuses the
   `csv-records` bytes, so the comparison starts from a dataset that already
   exists.
2. **`nullable-sum` (component): branchy validity bitmap.** The
   `nullable-columns` generator is implemented and tested but no workload
   consumes it. A masked aggregation adds branch prediction and a bitmap read to
   the existing arithmetic/indirection/hashing set.
3. **`parallel-groupby` (component): threads.** Everything is single-threaded.
   A partitioned parallel aggregation tests thread runtimes, partitioning and
   merge — and needs a documented core count, because the number only means
   something with the machine's parallelism attached.
4. **`numeric-kernel` (micro): does the 2.14× survive autovectorization?**
   A dense kernel with an explicit SIMD-friendly form would separate "bad scalar
   codegen" from "no vectorization" in the `numeric-scan` gap. Worth doing only
   with a written question; otherwise it is compiler benchmarking.

Not next: another sort or another join (no new dimension), microbenchmarks
without a question, and anything that would need Python at run time.

## How to check these numbers yourself

```bash
.venv/bin/mpf validate                      # specs and committed artifacts
cd moonperf
moon run cli --target native -- report ../results/<workload>/<artifact>.json --out /tmp/report.md
```

The report is generated from the artifact, never edited by hand; regenerating a
committed report must produce the same file. To re-measure, follow protocol §10
and the workload README; a diagnostic run writes under `results/tmp/` and is not
an artifact of record.
