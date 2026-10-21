# numeric-scan

**Tier:** micro · **Status:** active (v5; accepted artifact committed)

## Research question

What does a dense, sequential floating-point pass cost in MoonBit compared with
Rust, and where does the difference come from: loop code generation, bounds
checks, floating-point contraction, aliasing or call overhead?

The kernel is deliberately boring: one pass over an `f64` array, accumulating
`sum`, `sumsq`, `min`, `max` and the number of values above a threshold. There
is no algorithm to hide behind, no allocation in the inner loop and no data
structure to tune. If the two languages differ here, the difference belongs to
the compiler and the generated loop.

## Why this is first

It is the smallest workload that exercises the whole experiment loop:
deterministic dataset, exactly specified output, cheap to implement twice, and
sensitive enough to compiler decisions that a fair comparison is non-trivial. A
framework that cannot compare this kernel honestly will not compare a hash join
or a Parquet decoder honestly either — it will just have more variables to
blame.

## Dataset

`uniform-f64` with `count = 1_000_000`, seed `20261020`, values in `[-1, 1)`.
Generated little-endian `f64` bytes, 8 MB, no header; the harness records the
SHA-256 of the generated file in the result artifact. The generator is part of
the harness, not of any implementation: every implementation reads the same
bytes. The expected SHA-256 for this manifest is
`fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2`; the
MoonBit generator must reproduce it byte-for-byte before the experiment is
accepted.

## Output and correctness

Implementations emit a JSON object with `n`, `sum`, `sumsq`, `min`, `max` and
`count_above` through the adapter interface. Verification is `tolerance`
against the Rust reference, `rtol = 1e-9`, `atol = 0`, with integer fields
compared exactly.

The tolerance is not a way to make results pass: a skipped element or a
wrongly accumulated term moves `sum` by far more than `1e-9` relative at this
input size. The gate is shown to fail, not assumed to: the `demo-scan` runner
fixture injects a wrong output, a timeout and a build failure, and
`scripts/crosscheck-numeric-scan.py` can be pointed at a patched kernel. A C
build that starts its loop at element 1 instead of 0 moves `sum` by `0.33`
against a tolerance of `7.5e-7`, so the adapter is excluded before any timing
and never appears in the timing table.

## Implementations

| id | Language | Shape | State |
| --- | --- | --- | --- |
| `moonbit` | MoonBit | materializes an `f64` array after a length check, then scans it; `Bench::keep` barrier across repeats | Active; timed in the committed artifact |
| `rust` | Rust | reference: `Vec<f64>` load, `&[f64]` scan, `black_box` barrier across repeats | Active; reference for the correctness gate |
| `c` | C17 | portable little-endian load into a `double` array, plain pointer loop, empty-asm memory barrier across repeats, `-O3 -march=native` | Active; independent compiler check (P2) |

Each implementation gets its own result row; a deliberately different build
profile (for example `-O2` vs `-O3`) is a separate implementation id, not a
hidden flag. That is what makes the comparison auditable.

The C adapter exists to add a second compiler to the micro comparison: it
should land on the Rust median, and it does (1.5 % apart in the recorded run,
inside the sample CV). If it did not, the difference would belong to a
compiler flag or to the generated loop, not to the language.

### Fairness constraints

- All implementations load the dataset into the same in-memory representation
  before the kernel: an array of `f64`, one element per input. MoonBit
  materializes the array once after a length check, Rust loads a `Vec<f64>`, C
  loads a `double` array through a portable little-endian decode.
- All must check that the input length is a multiple of 8, and that `n` matches
  the dataset count.
- All must use the same threshold and the same comparison (`value > threshold`).
- All must print round-trippable floats; `n` and `count_above` are JSON
  integers. C prints `%.17g` and appends `.0` when the value is integral.
- All must use the released native build. A different profile is a different
  implementation id.
- The `--repeat K` loop must not be hoisted. Use a compiler barrier
  (`Bench::keep`, `black_box`, an empty asm with a memory clobber or
  equivalent) and verify that the `K = 10 -> 20` slope equals about ten
  kernels for this CPU-bound kernel.
- The harness times one process invocation with `--repeat K`; the adapter does
  not report its own time. The setup baseline (`--repeat 0`) is recorded by the
  harness, not subtracted.

## Measurement notes

The manifest uses `warmup = 3`, `repeats = 20`, `inner_repeats = 200`,
`timeout_s = 120` and `max_cv = 0.05` (version 5; v4 changed the measurement
and v5 only flips the lifecycle status to active). The setup baseline is the
median of three `K = 0` invocations.

Two `ok` artifacts are committed:

| Artifact | Implementations | Medians (ns/iter) | CV | Setup fraction |
| --- | --- | --- | --- | --- |
| `20261021T053956Z-f1d6607a505a` | rust, moonbit | rust 1014994.5, moonbit 2221970.5 | 3.26 % / 3.05 % | 2.6 % / 1.5 % |
| `20261021T055715Z-a47130edbf4b` | c, rust, moonbit | c 1058107, rust 1042542.5, moonbit 2228174 | 3.62 % / 3.99 % / 1.90 % | 3.7 % / 3.5 % / 2.0 % |

The second artifact is the one of record for the three-implementation
comparison; the first remains valid for its two implementations. Both are from
a clean build and a recorded host, and both pass the `K=10 -> 20` slope check.

The runner also checks the `K=10 -> 20` slope; it should be about ten kernels,
and a slope ratio below 0.5 is flagged as suspected optimizer elimination.
Do not relax `max_cv` to make a run pass.

## What would falsify the experiment

- The same implementation re-run on the same machine produces medians that
  differ by more than the measured effect.
- The correctness gate cannot be made to fail when a fault is injected.
- The implementations do not read byte-identical input.
- The implementations do not share the same setup representation and input
  validation.
- The timeout leaves an orphan process that runs during the next sample.

Any of these invalidates the comparison, and is reported as a harness or
workload bug — not as a language result.
