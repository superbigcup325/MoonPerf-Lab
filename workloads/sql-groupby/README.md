# sql-groupby

**Tier:** end-to-end · **Status:** active (v1)

## Research question

Read a CSV table, parse it, group by one integer column and aggregate a second
one. What does that whole path cost — and what does a query engine add over a
hand-written pipeline that knows the query in advance?

This is the first end-to-end workload and the first one that consumes another
project's public interface. It answers two separate questions and does not
pretend they are one:

- **like-for-like:** hand-written MoonBit, Rust and C pipelines over the same
  bytes — a language and code-generation comparison;
- **engine versus pipeline:** the same query executed by
  [moonlake](https://github.com/superbigcup325/moonlake) 0.3.1 through its
  public API (a CSV scan source, a catalog, `execute`) — the cost of parsing
  SQL, binding, planning and scanning on top of the work above.

## Dataset

`csv-records` with `count = 2_000_000`, seed `20261026`, `categories = 16` and
`amount_max = 1_000_000`: a 33 415 933-byte ASCII table, header included, with
SHA-256 `d397e837ad352e06ec3d306fbe52fca32c98574a0fd3d58e2b06a7b37f45a441`.

```
id,category,amount
0,0,911719
1,14,615528
...
```

`id` is the row index, `category` is uniform in `[0, 16)` and `amount` is
uniform in `[0, 1_000_000]`. Every implementation reads this one file.

## The query and the output

The workload is one fixed statement, so a hand-written pipeline can answer it
without a parser:

```sql
SELECT category, count(*) AS n, sum(amount) AS total
FROM t GROUP BY category ORDER BY category
```

| Field | Type | Meaning |
| --- | --- | --- |
| `groups` | integer | rows the query returns |
| `rows` | integer | input rows aggregated |
| `checksum` | string | 16 lowercase hex digits |

`checksum` folds the result rows in `ORDER BY category` order: for output row
`i` (0-based), add `n_i * (i + 1) + total_i` to a wrapping 64-bit accumulator.
The position weight makes a skipped row, a permuted row and a wrong `n` all
change the answer, not just the set of values.

Verification is `exact` against the Rust reference. Fault injection is
recorded, not promised. Two injected faults on the C adapter:

| Fault | `rows` | `checksum` | Verdict |
| --- | ---: | --- | --- |
| none (correct) | 2 000 000 | `000000e8c9b50b01` | passes |
| odd rows skipped | 1 000 000 | `000000746c5495a4` | fails on `rows` and `checksum` |
| group weight dropped from the checksum | 2 000 000 | `000000e8c8d001eb` | fails on `checksum` |

## Implementations

| id | Language | Shape | State |
| --- | --- | --- | --- |
| `rust` | Rust | reference: hand-written CSV scan over the raw bytes, dense 4096-slot category tables, no SQL parser; `black_box` across repeats | Reference |
| `c` | C17 | the same hand-written pipeline; empty-asm barrier across repeats | Timed |
| `moonbit` | MoonBit | the same hand-written pipeline; `Bench::keep` across repeats | Timed |
| `moonlake` | MoonBit (moonlake 0.3.1) | CSV scan source registered in a catalog; the SQL text is parsed, bound, planned and executed per pass through `@moonlake.execute` | Timed |

### Fairness constraints

- All four read the same file and answer the same question; the hand-written
  three do not include a SQL parser, and the adapter summaries say so. The
  engine column is therefore not a language comparison — compare `moonlake`
  against the others only as engine versus pipeline.
- The hand-written implementations use one dense 4096-slot table per aggregate
  and emit slots in ascending order, which is the `ORDER BY category` order the
  SQL path produces. A different layout is a different implementation id.
- Every implementation re-reads and re-parses the file inside the timed kernel
  on every pass: this is an end-to-end workload, so I/O and parsing are part of
  the number, not setup.
- The kernel must not be hoisted: `black_box` / `Bench::keep` / empty-asm
  barrier, and the `K = 10 -> 20` slope stays near linear.
- The `moonlake` adapter depends on the published `superbigcup325/moonlake@0.3.1`
  from mooncakes; `moon update` is required once on a fresh toolchain so the
  registry knows the version, and the build fails loudly if it does not.

## Measurement notes

`warmup = 3`, `repeats = 20`, `timeout_s = 120`, `inner_repeats = 10`,
`max_cv = 0.05`. One pass is about 27 ms for the hand-written pipelines and
about 170 ms for the engine at 2 000 000 rows, so a sample is 0.3 s and 1.7 s
respectively; the setup baseline stays under 4 % for all four.

The artifact of record is `results/sql-groupby/` (see the results index). The
shape to read from it:

- the three hand-written pipelines land within about 7 % of each other, with
  MoonBit at 1.07× the Rust median;
- the engine is about 6× the Rust median for this query at this size.

The engine number is a *path* measurement: parsing SQL, binding, planning and
the scan source's own CSV reader are inside it, and a hand-written pipeline
skips all of that by construction. It is not evidence that one language is
faster than another.

## What would falsify the experiment

- The engine and the hand-written pipelines read different bytes, or the
  engine's inferred column types change the answer (a `sum` that widens to
  float would change `total`).
- An injected fault (a skipped row, a dropped group weight, a permuted result)
  passes the gate.
- The engine is credited with work it did not do — for example if the scan
  source were cached between passes, or if `execute` were given a plan instead
  of the SQL text.
- The timeout leaves an orphan process that runs during the next sample.
