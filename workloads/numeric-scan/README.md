# numeric-scan

**Tier:** micro · **Status:** draft (specified, not yet measured)

## Research question

What does a dense, sequential floating-point pass cost in MoonBit compared with
Rust and C, and where does the difference come from: loop code generation,
bounds checks, floating-point contraction, aliasing or call overhead?

The kernel is deliberately boring: one pass over an `f64` array, accumulating
`sum`, `sumsq`, `min`, `max` and the number of values above a threshold. There
is no algorithm to hide behind, no allocation in the inner loop and no data
structure to tune. If the two languages differ here, the difference belongs to
the compiler and the generated loop.

## Why this is first

It is the smallest workload that exercises the whole experiment loop:
deterministic dataset, exactly specified output, cheap to implement three
times, and sensitive enough to compiler decisions that a fair comparison is
non-trivial. A framework that cannot compare this kernel honestly will not
compare a hash join or a Parquet decoder honestly either — it will just have
more variables to blame.

## Dataset

`uniform-f64` with `count = 1_000_000`, seed `20261020`, values in `[-1, 1)`.
Generated little-endian `f64` bytes, 8 MB, no header; the harness records the
SHA-256 of the generated file in the result artifact. The generator is part of
the harness, not of any implementation: every implementation reads the same
bytes.

## Output and correctness

Implementations emit a JSON object with `n`, `sum`, `sumsq`, `min`, `max` and
`count_above` through the adapter interface. Verification is
`tolerance` against the Rust reference, `rtol = 1e-9`, `atol = 0`, with integer
fields compared exactly.

The tolerance is not a way to make results pass: a skipped element or a
wrongly accumulated term moves `sum` by far more than `1e-9` relative at this
input size. The acceptance test for the workload is an implementation with an
intentionally skipped element, which must fail correctness and must therefore
never appear in the timing table.

## Implementations

| id | Language | Shape |
| --- | --- | --- |
| `moonbit` | MoonBit | safe loop over the array; no `unsafe` unless a variant is declared as a separate implementation |
| `rust` | Rust | reference: `&[f64]` slice, bounds elision verified in the release build |
| `c` | C17 | plain pointer loop, `-O3 -march=native` recorded in the build log |

Each implementation gets its own result row; a deliberately different build
profile (for example `-O2` vs `-O3`) is a separate implementation id, not a
hidden flag. That is what makes the comparison auditable.

## What would falsify the experiment

- The same implementation re-run on the same machine produces medians that
  differ by more than the measured effect.
- The correctness gate cannot be made to fail when a fault is injected.
- The three implementations do not read byte-identical input.

Any of these invalidates the comparison, and is reported as a harness or
workload bug — not as a language result.
