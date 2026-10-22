# Measurement noise on this host

The P3 regression verdict needs a minimum detectable effect that comes from
data. This page is that data: three baseline campaigns of 20 runs each — micro
and both component workloads — with the same workload version, the same dataset,
the same bytes and no code change between runs. Every difference here is the
host, not the code. The end-to-end workload has no completed campaign yet; the
reason is part of the result and is recorded below.

It is a measurement of **one laptop in one window**, and it is written down
because the alternative — choosing a threshold because 5 % sounds reasonable —
is what the repository forbids.

## Method

```bash
scripts/measure-baseline.sh numeric-scan 20
scripts/measure-baseline.sh gather 20
scripts/measure-baseline.sh hash-join 20
scripts/false-positive-rate.py results/tmp/baseline/*      # the tables below
# the end-to-end workload needs a writable registry for its engine adapter:
MOON_HOME=$PWD/.moon-home scripts/measure-baseline.sh sql-groupby 20
```

- Runs are strictly sequential, never parallel; each is a full harness run with
  its own builds outside the timed region, so the campaign is exactly what a
  developer does repeatedly.
- The campaign log records the UTC time, the load average and the current core
  frequency window before every run.
- A pair is two runs of unchanged code, so every flag a threshold raises on a
  pair is a false positive. `FP @ x %` is the share of pairs that differ by more
  than `x %`; with 20 runs there are 190 pairs, so the rate is resolved to about
  ±1.5 percentage points.
- Host: 12th Gen Intel Core i5-12500H, 16 logical CPUs, `powersave` governor,
  16 GB RAM, CachyOS, Linux x86_64 — the same host every committed artifact was
  measured on.

## What one run tells you, and what it does not

The harness reports a coefficient of variation over the 20 samples *inside* one
run. That number is not the noise a regression check faces: a check compares a
run against a **different** run, and the host drifts between them. The campaign
measures the second thing.

Table: absolute medians across 20 runs (`p50`/`p95` are pairwise differences;
`CV` is the median within-run value; `FP` is the false-positive rate of that
threshold).

| Workload | Implementation | median per run | spread max/min | CV | p50 | p95 | FP @ 2 % | FP @ 5 % | FP @ 8 % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `numeric-scan` | C17 | 960 969 | 5.7 % | 1.85 % | 1.3 % | 5.1 % | 47.9 % | 7.9 % | 0.0 % |
| `numeric-scan` | Rust | 952 079 | 5.5 % | 1.46 % | 1.7 % | 5.1 % | 47.4 % | 6.3 % | 0.0 % |
| `numeric-scan` | MoonBit | 2 118 733 | 5.0 % | 1.34 % | 1.6 % | 4.4 % | 46.8 % | 0.0 % | 0.0 % |
| `hash-join` | C17 | 20 263 985 | 10.4 % | 3.17 % | 2.9 % | 8.9 % | 58.4 % | 38.4 % | 10.5 % |
| `hash-join` | Rust | 21 662 903 | 15.8 % | 3.49 % | 4.0 % | 12.5 % | 66.8 % | 48.4 % | 35.3 % |
| `hash-join` | MoonBit | 22 283 482 | 12.4 % | 3.36 % | 3.2 % | 9.7 % | 59.5 % | 37.4 % | 11.6 % |
| `gather` | C17 | 9 878 761 | 7.8 % | 1.56 % | 0.9 % | 6.7 % | 34.7 % | 24.7 % | 0.0 % |
| `gather` | Rust | 8 079 154 | 11.7 % | 2.15 % | 1.9 % | 9.9 % | 47.9 % | 26.8 % | 17.4 % |
| `gather` | MoonBit | 16 296 166 | 7.9 % | 1.88 % | 1.4 % | 6.4 % | 36.8 % | 17.4 % | 0.0 % |

Three things stand out.

**A 5 % threshold would be wrong for every workload here.** It fires on up to
8 % of unchanged numeric-scan pairs, on 17–27 % of gather pairs and on 37–48 % of
hash-join pairs. The same threshold that looks conservative for one workload is
almost noise-tolerant for another.

**The within-run CV is a floor, not the noise.** `2·√2·CV` (the two-sample
width of a difference at one sigma each) lands close to the observed `p95` for
numeric-scan (3.8–5.2 % predicted against 4.4–5.1 % measured), but it misses the
tail on the bursty workloads: gather predicts 4.4–6.1 % against 6.4–9.9 %
measured, and hash-join's measured tail reaches 12.5 % where the model says 9.9 %
at most. A threshold derived only from CV will call real regressions noise.

**The distribution is bimodal, not Gaussian.** gather's median pairwise
difference is 0.9 % while its p90 is 6.5 %: most runs agree closely and a few
are taken during a busy window. No single threshold models that honestly; it is
an argument for paired designs (measure both sides in the same condition) over
unpaired thresholds.

## Comparing implementations is much cheaper than comparing runs

The harness already measures all implementations round-robin inside one run, so
a ratio `subject / baseline` shares the run's conditions. That ratio is the
robust instrument:

| Workload | Ratio | median | spread max/min | p50 | p95 |
| --- | --- | ---: | ---: | ---: | ---: |
| `numeric-scan` | `c` / `rust` | 1.0097 | 2.2 % | 0.58 % | 1.66 % |
| `numeric-scan` | `moonbit` / `rust` | 2.2171 | 2.3 % | 0.55 % | 1.53 % |
| `hash-join` | `c` / `rust` | 0.9293 | 6.6 % | 1.95 % | 5.40 % |
| `hash-join` | `moonbit` / `rust` | 1.0238 | 5.8 % | 1.88 % | 4.72 % |
| `gather` | `c` / `rust` | 1.2251 | 4.8 % | 1.13 % | 3.33 % |
| `gather` | `moonbit` / `rust` | 2.0151 | 5.9 % | 1.10 % | 4.69 % |

The absolute medians of the same runs move 5–16 %; the ratios move 2–6 %. A
language or implementation comparison is therefore roughly three times more
precise than a same-code run-to-run comparison, and it costs nothing extra: the
harness already does it.

## A historical baseline is not a baseline

Same workload version, same dataset SHA-256, same host, one day apart:

| Workload | Implementation | 2026-10-21 artifact | 2026-10-22 campaign median | absolute drift | same ratio drift |
| --- | --- | ---: | ---: | ---: | ---: |
| `numeric-scan` | C17 | 1 058 107 | 960 969 | −9.2 % | `c/rust` −0.5 % |
| `numeric-scan` | Rust | 1 042 542 | 952 079 | −8.7 % | — |
| `numeric-scan` | MoonBit | 2 228 174 | 2 118 733 | −4.9 % | `moonbit/rust` +3.7 % |
| `hash-join` | C17 | 22 005 496 | 20 263 985 | −7.9 % | `c/rust` +2.7 % |
| `hash-join` | Rust | 24 314 815 | 21 662 903 | −10.9 % | — |
| `hash-join` | MoonBit | 24 718 417 | 22 283 482 | −9.9 % | `moonbit/rust` +0.7 % |
| `gather` | C17 | 10 109 470 | 9 878 761 | −2.3 % | `c/rust` +0.8 % |
| `gather` | Rust | 8 314 059 | 8 079 154 | −2.8 % | — |
| `gather` | MoonBit | 16 577 759 | 16 296 166 | −1.7 % | `moonbit/rust` +1.1 % |

Identical code and identical bytes differ by up to 10.9 % between sessions, and
the difference has a direction (today's session is faster, i.e. the machine was
in a different frequency/thermal state). Any verdict that compares a new run
against an old artifact on absolute time would report a 5–11 % "regression" that
is nothing of the sort. The ratios absorb most of it (0.5–3.7 %), but not all:
`moonbit/rust` on numeric-scan still moved 3.7 %, which means even a ratio needs
a same-session or paired baseline for effects below about 4 %.

## The stability gate is itself noisy

The 5 % CV gate rejected **1 of 20** numeric-scan runs, **6 of 20** gather runs
and **6 of 20** hash-join runs — unchanged code, unchanged data. On this host
those two workloads sit close enough to the gate that a third of their runs are
rejected without anything being wrong.

The end-to-end campaign never completed, and that is the clearest evidence in
this document. The first attempt reached run 8 when a background process pushed
the load average from 0.6 to 4.1; that run came back with CV 22.8 / 19.3 / 21.6
/ 24.1 % across its four implementations and a suspected-elimination note on the
engine path, and the gate rejected it. The second attempt started at a load
average of 11 and was abandoned after one run: at that point the measurement is
the machine, not the workload. A shared laptop cannot be depended on for a
calibration campaign, which is exactly why the roadmap asks for a designated
measurement host before P3 can claim a false-positive rate.

Consequences for reading the record: "unstable" means *this run cannot support a
claim*, not *the machine was broken and the workload is fine*. Conversely, an
`ok` run is not evidence that the next run will be `ok`.

## What this means for the regression verdict (P3.2)

Numbers below are what the data supports on this host today; they are inputs to
the design, not a design yet.

1. **Refuse cross-session absolute comparisons.** A subject run and a baseline
   artifact from another window are `not_comparable` at this noise level; the
   verdict must require a same-session (or interleaved) baseline.
2. **Primary instrument: the within-run ratio**, whose measured `p95` on this
   host is 1.7 % (numeric-scan), 4.7–5.4 % (gather, hash-join). Absolute medians
   need roughly 5–13 % before they mean anything.
3. **MDE = the empirical `p95` of the relevant baseline campaign**, not a
   constant and not `2·√2·CV` alone; the CV model is a floor, and the code should
   say which of the two it used.
4. **Both sides must be `ok`.** A run rejected by the stability gate contributes
   no comparison, and the verdict should report how many candidate runs it had to
   discard instead of silently picking one.
5. **The end-to-end tier needs its own campaign** on a host that holds still; the
   engine path's 160 ms iterations may be friendlier than the component
   workloads, but that is a guess until it is measured.
6. **Twenty runs is enough to size a threshold, not enough to publish a
   false-positive rate with confidence.** The next campaign should span several
   windows (morning/evening, quiet/busy) so the estimate covers what daily use
   will actually see — and it needs a host that is not also running someone's
   editor and browser.

## Limits

- One host, one window per workload (~8 minutes for numeric-scan, ~13 for each
  component workload), shared with whatever else the machine was doing; the load
  average during the completed campaigns was 0.6–2.2, and it reached 4.1 and then
  11 during the abandoned end-to-end attempts.
- No campaign covers the end-to-end tier, so the engine path's ratio noise is
  unknown; do not assume it matches the component workloads.
- The pairwise estimate treats 190 pairs as independent; they are not, so the
  confidence interval is wider than the ±1.5 points a binomial count suggests.
- Only two sessions exist so far (2026-10-21 and 2026-10-22), so the
  cross-session figure is one observation, not a distribution.
- Nothing here measures a workload under deliberate contention (nice, cgroups,
  CPU pinning); that is a designated-host question, not a verdict question.

## Reproduction

The campaign artifacts stay in `results/tmp/baseline/<workload>/run-NN/`: they
are diagnostics, not artifacts of record, so they are not committed. Re-running
the two scripts above reproduces the method and the shape of these tables; the
digits belong to the window they were measured in, which is the point.
