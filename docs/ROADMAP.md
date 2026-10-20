# Roadmap

MoonPerf Lab is a reproducible performance experiment and optimization
framework for the MoonBit ecosystem. Moonlake is its first validation project;
it is not the whole of the lab.

The roadmap follows one order: **prove that an experiment is trustworthy
before adding benchmarks, and close one optimization loop before building a
general platform.** A phase is done when its exit criteria are met with
artifacts in this repository, not when its tasks are ticked off.

## At a glance

| Phase | Outcome | Status |
| --- | --- | --- |
| **P0 · Foundation** | Experiment protocol, result format, project skeleton | In place (2026-10-20) |
| **P1 · MVP** | One end-to-end, reproducible experiment | Next |
| **P2 · Coverage** | A representative benchmark suite | After MVP |
| **P3 · Automation** | CI, history and regression detection | After P2 |
| **P4 · Research** | Optimization research capability | After MVP is stable; no deadline |

---

## P0 · Protocol and project boundary — in place

**Estimated effort:** 2–4 days.

**Goal:** define what makes a result credible before the framework grows, so
that MoonBit and Rust/C can be compared fairly later.

Completed in this repository:

- [x] Benchmark directory, naming and version-management rules
      ([protocol §3](experiment-protocol.md#3-repository-layout-naming-and-versions))
- [x] A single workload description format
      ([`workloads/numeric-scan/workload.toml`](../workloads/numeric-scan/workload.toml),
      [`schemas/workload.schema.json`](../schemas/workload.schema.json))
- [x] The adapter interface for language implementations
      ([protocol §5](experiment-protocol.md#5-adapter-interface))
- [x] Compile modes, optimization levels, warmup and repeat rules
      ([protocol §7](experiment-protocol.md#7-measurement))
- [x] Recorded metadata: CPU, OS, compiler versions, flags, git commit, dataset
      identity ([protocol §8](experiment-protocol.md#8-metadata))
- [x] Micro, component and end-to-end tiers
      ([protocol §1](experiment-protocol.md#1-terms-and-tiers))
- [x] Result schema and raw-sample format
      ([`schemas/result.schema.json`](../schemas/result.schema.json))
- [x] Minimum project skeleton with a validating harness CLI
      ([`mpf/`](../mpf/), CI)

**Deliverables:** the protocol document, the three schemas, the workload
skeleton, and a harness that validates them.

**Acceptance:** a developer can add a workload without changing the harness
core, and `mpf validate` plus CI tells them whether the specification is
consistent.

**Not yet done (moved into P1):** freezing the initial Moonlake baseline. A
baseline is only meaningful once the runner and at least one reference
implementation exist.

---

## P1 · MVP — one complete performance experiment

**Estimated effort:** 1–2 weeks.

This is the most important milestone. The MVP has no web UI, no database and no
plugin system.

| Module | Minimum requirement |
| --- | --- |
| Workload | Describes input data, parameters and the expected output |
| Runner | Builds, executes, enforces timeouts and records failures uniformly |
| Adapter | At least MoonBit plus one Rust/C reference implementation |
| Correctness | Checks output equality or tolerance; failing results never enter the timing table |
| Measurement | Warmup, repeated measurement, raw samples retained |
| Metadata | Environment, commit, build configuration and dataset identity recorded |
| Report | Markdown report plus machine-readable JSON |
| Reproducibility | Results reproducible from a clean environment by following the docs |

### MVP workflow

1. **Select the experiment.** Workload, input size, implementation versions.
2. **Build and execute.** Uniform parameters, timeout, error capture.
3. **Verify correctness.** Compare outputs or checksums; a mismatch fails the
   run.
4. **Repeat the measurement.** Keep raw durations, statistics and environment
   metadata.
5. **Generate a reproducible report.** Comparison, sample distribution,
   reproduction command.

### The first workload

`numeric-scan` (see [`workloads/numeric-scan/`](../workloads/numeric-scan/))
is deliberately simple: one sequential pass over `f64` data, an easily checked
output, and no algorithm or file-format complexity to blame. If it cannot be
compared fairly, repeated and recorded completely, a hash join or Parquet
benchmark will only amplify the problem.

### MVP acceptance

The milestone is complete only when all five hold:

1. The same workload runs under MoonBit and a Rust/C reference.
2. The correctness gate detects a deliberately injected error.
3. Repeated runs produce complete raw samples and a summary report.
4. After changing the commit, the code version behind an experiment is
   unambiguous.
5. Another developer can reproduce the whole flow from the documentation.

The acceptance criterion is not that one language is faster.

---

## P2 · A representative benchmark suite

**Estimated effort:** 2–4 weeks, after the MVP.

**Goal:** grow from a single numeric kernel to an experiment matrix that can
explain Moonlake's performance.

| Priority | Benchmark | Research question |
| --- | --- | --- |
| P0 | Numeric Scan | Loops, numeric operations, bounds checks and compiler optimization |
| P0 | Hash Join | Hash tables, memory access, data distribution and collision handling |
| P1 | Columnar Gather | Indirect addressing, data layout and cache locality |
| P1 | Parquet Decode | Decoding cost, batching and type conversion |
| P2 | End-to-end SQL | Multi-operator composition, query plans and overall execution efficiency |

Design requirement: every benchmark class includes multiple input sizes and
distributions. A hash join is not "uniform keys only" — table sizes, key
distribution and match rate all change the answer.

Each benchmark carries:

- a kernel that can run on its own;
- a correctness cross-check between MoonBit and the reference;
- several representative input scales;
- raw performance samples and environment information;
- a performance-difference report against the previous version.

**Exit:** the lab produces a representative, reproducible performance portrait
of Moonlake, not a single aggregate score.

---

## P3 · Automation, history and performance regressions

**Estimated effort:** 1–2 weeks.

**Goal:** make the lab a daily development tool instead of a manual experiment
rig.

- Run correctness checks in GitHub Actions.
- Run performance experiments on a designated machine and store the results.
- Link results to commit, PR, compiler version and environment.
- Produce performance trends across versions.
- Alert on regressions while distinguishing a real regression from measurement
  noise.
- Re-run the complete configuration of any stored experiment.

Important boundary: a shared CI runner is not a precision measurement
instrument. CI checks correctness and coarse-grained regressions; formal
performance numbers come from a fixed hardware profile with the environment
recorded.

**Exit:** Moonlake's performance changes are tracked continuously, and a
developer can answer "which workload did this change make faster or slower?"

---

## P4 · Optimization research capability

Starts once the MVP is stable. No hard deadline.

This is where the lab's long-term differentiation lives:

- **Profiling:** optional integration with CPU profilers and hardware
  performance counters.
- **Bottleneck attribution:** break an overall gap down into computation,
  memory access, allocation and decoding.
- **Experiment matrix:** automatically combine build configurations, input
  sizes, data distributions and implementation versions.
- **Cross-project adapters:** let other MoonBit projects plug in without
  rewriting the framework.
- **Optimization verification:** record before/after performance and require
  correctness to be unchanged.
- **Research reports:** evidence chains usable for project iterations, articles
  and optimization proposals.

This phase must not promise to find every bottleneck automatically.
Attribution combines profilers, experimental design and human analysis; a table
of elapsed times is not enough.

---

## MVP scope boundary

To keep the project from over-designing, the first version excludes the
following.

**MVP must have:** command-line runner, unified adapter interface, correctness
verification, repeated measurement, JSON/Markdown reports, experiment
metadata, reproduction instructions.

**Later:** web dashboard, database, distributed execution, automatic parameter
search, a complex plugin system, automatic bottleneck diagnosis.

---

## Execution checklist

| # | Item | Timing | Status |
| --- | --- | --- | --- |
| 1 | Experiment protocol and result schema | Days 1–3 | Done (P0) |
| 2 | Runner and adapter interface | Days 4–7 | Not started |
| 3 | A complete numeric-scan comparison | Week 2 | Not started |
| 4 | Reporting and reproduction flow | Week 2 | Not started |
| 5 | Hash join and gather coverage | Weeks 3–4 | Not started |
| 6 | Evaluate CI and regression detection | Week 4+ | Not started |

Estimates assume one developer and an existing Moonlake checkout and test
environment.

## Near-term target

The first target is: **a genuinely reproducible `numeric-scan` experiment
within two weeks.** No dashboard before that, and no attempt to cover every
operator. If the project pauses afterwards, it still leaves a working
experiment tool and a baseline that Moonlake can use.
