# MVP specification

**Status:** P1 target, reviewed 2026-10-20. P1.1 is in progress: the MoonBit dataset, manifest, statistics and `list`/`validate` CLI are done; the runner, artifact and report are still Python.

## Definition

The MVP is **one complete, reproducible cross-language experiment** that a
second person can re-run from the repository and its recorded environment.

It is complete when `numeric-scan` runs under a MoonBit implementation and a
Rust reference on one recorded host, the correctness gate has been shown to
fail on an injected fault, raw samples and environment metadata are in a JSON
artifact, a Markdown report is generated from that artifact, and the MoonBit
program — not Python — owns the experiment loop.

It is not complete when a benchmark exists. A benchmark without a verified,
reproducible experiment is a workload, not an MVP.

## In scope

| Area | MVP requirement | Status target |
| --- | --- | --- |
| Workload definition | `workload.toml` + adapter contract, validated | Keep the protocol v1 structure; add the `--repeat 0` setup baseline |
| Framework core | MoonBit CLI owning manifest, dataset, host calls, verify, measure, artifact, report, orchestration | Replace the Python bootstrap |
| Implementations | MoonBit `numeric-scan` + Rust reference | Fix the existing drafts; C is P2 |
| Build | Build from clean, record command, toolchain, duration, log hash | Add clean-build rule |
| Run | One child process per sample, process-group timeout, exit-code/stdout/stderr capture | Add process-group kill |
| Correctness | Reference-first, exact/tolerance, type-aware, fault injection | Fix reference ordering; add fixtures |
| Measurement | Warmup, `repeats`, `inner_repeats`, round-robin, raw samples, CV gate | Tune `K`; add setup baseline |
| Metadata | Commit, dirty flag, branch, toolchain, build config, dataset identity, host | Keep; generalize harness metadata |
| Artifact | JSON source of truth; schema-valid; raw samples; reproduction command | Keep; language-neutral `harness` |
| Report | Generated Markdown, never hand-edited | Keep; portable to MoonBit |
| Reproduction | Clean-environment path; same-host medians within ±5 % | Document and test |
| CI | `moon check`/`moon test`, Rust build, Python schema cross-check; correctness only | Add after the core exists |
| Commit hygiene | Incremental, traceable commits | Required for the hackathon |

## Scope ladder

| Horizon | Includes | Excludes |
| --- | --- | --- |
| **MVP (P1, must)** | One MoonBit-owned experiment loop; numeric-scan; MoonBit + Rust; correctness and fault injection; timeout; raw samples; setup baseline; metadata; JSON + Markdown; clean reproduction | Every other workload; C reference; history; CI performance; profiling; dashboard |
| **Immediately after MVP (P2–P3)** | C reference; 3–4 representative workloads; reusable generators; result history; CI correctness; noise-aware regression detection | Profiling and attribution; cross-project adapters; automatic diagnosis |
| **Mid/long-term (P4)** | Profiling integration; bottleneck attribution; experiment matrices; cross-project reuse; optimization verification; research reports | Automatic bottleneck diagnosis; an AI optimizer; a distributed cluster; a SaaS |
| **Not in the current roadmap** | Web dashboard; database; distributed execution; automatic parameter search; automatic bottleneck diagnosis; plugin system; leaderboard/aggregate score; cross-machine absolute comparison | — |

The MVP acceptance focus is **experiment trustworthiness, reproducibility and
architecture extensibility**, not the number of benchmarks and not whether
MoonBit wins. A valid loss, tie or unstable result is a valid MVP outcome.

## Functional requirements

### F1. MoonBit CLI

`mpf` is a native MoonBit binary with four commands:

```text
mpf list [root]
mpf validate [paths] [--result FILE]
mpf run <workload> [--out DIR]
mpf report <artifact.json> [--out FILE]
```

- `list` prints workloads, versions, tiers, statuses and discovered
  implementations.
- `validate` checks manifests, adapters, scripts, schemas and result artifacts;
  it reports all problems it can, not just the first.
- `run` performs the full experiment and writes the artifact and report.
- `report` regenerates the Markdown from an artifact; it never measures.

The CLI exits nonzero on invalid input or an `invalid` verdict.

### F2. Manifest and adapter validation

- Parse `workload.toml` and every `implementations/<id>/adapter.toml`.
- Enforce the JSON Schema and the semantic rules: `name` matches the directory;
  `verify.reference` names a discovered implementation; `run.sh` is executable;
  `dataset.generator` is implemented; `tier` is one of `micro`, `component`,
  `end-to-end`; tolerance mode has `rtol`; `status` transitions are valid.
- Reject unknown fields where the schema forbids them.
- The TOML parser yields typed values; a small converter maps them to the
  core value type. Validate with a targeted validator for the repository's
  closed schemas (or a general MoonBit JSON Schema library if it passes the
  repository cases). The Python `jsonschema` run is the independent oracle.
- Report `path: message` errors and continue validating other workloads.
- The MoonBit `validate` command now checks the real workloads. The Python
  `mpf validate` remains the independent oracle during the port.

### F3. Dataset

- Generate `uniform-f64` exactly as
  [`experiment-protocol.md`](experiment-protocol.md#4-dataset-contract)
  specifies.
- Cache it under `.data/` and verify its SHA-256 before use.
- Record generator, count, seed, params, SHA-256 and byte size in the artifact.
- Regenerate a missing or truncated cache file. If an existing file has the
  wrong size or hash, fail loudly instead of overwriting it: the mismatch may
  mean the generator, params or cache was changed, and overwriting hides the
  evidence.
- The MoonBit generator must reproduce the Python generator byte-for-byte for
  the committed manifest. The current expected SHA-256 for
  `count=1000000, seed=20261020, min=-1.0, max=1.0` is
  `fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2`;
  it is a golden test, not a value to hard-code into the generator. The
  MoonBit CLI reproduced it on 2026-10-20, and `cmp` confirmed byte-identical
  output against the Python generator.

### F4. Build

- Run `build.sh` from the implementation directory with a timeout.
- Build from a clean state. P1 adds an optional `build_dir` to `adapter.toml`;
  the harness removes that directory before building. If `build_dir` is absent,
  the harness builds in a temporary copy of the implementation directory that
  excludes VCS-ignored paths and the known output directories. A build that only
  succeeds incrementally is not a clean build.
- Record whether the build ran, its command, duration, log SHA-256 and log tail.
- A failed build excludes that implementation, records the failure and makes
  the verdict `invalid`.
- The build is outside the timed region.

### F5. Correctness gate

- Verify the reference implementation **first**; if it fails, no other
  implementation can be verified and the verdict is `invalid`.
- Compare the declared fields only; extra fields are ignored.
- Exact mode: type and value must match.
- Tolerance mode: floats use `|subject - reference| <= atol + rtol * |reference|`;
  non-floats are compared exactly; JSON type matters (an integer is not a
  float).
- Missing fields fail. `NaN`/`Infinity` fail. Non-scalar values fail.
- When the workload declares an input count field (numeric-scan uses `n`), the
  harness checks it against the dataset count independently of the reference.
  Two implementations can agree on a wrong count; the reference is not the only
  oracle for facts the harness knows.
- A failing implementation is recorded with its errors, carries no samples and
  is never quoted.
- Fault injection is a required acceptance test: a deliberately wrong
  implementation must fail the gate. A gate that cannot fail is a bug.

### F6. Measurement

- Build, then correctness, then warmup, then measurement.
- Warmup invocations are discarded.
- Measurement rounds: each round runs every valid implementation once; the
  starting implementation rotates (round-robin) to spread drift.
- Each sample is one fresh process invocation with `--repeat K`; the recorded
  per-iteration time is `wall_ns / K`.
- The `K` repetitions must not be hoisted by the optimizer. The adapter uses a
  compiler barrier (`Bench::keep`, `black_box`, a volatile sink or an
  equivalent). The harness runs a scaling diagnostic outside the recorded
  samples: after subtracting the setup baseline, `K = 10` should cost about 10×
  `K = 1` for a CPU-bound kernel. A flat curve is a bug, not a fast
  implementation.
- Record every raw sample. Do not trim outliers. Compute median, mean, min,
  stdev and CV from the samples in the artifact.
- If `cv > max_cv` (default 0.05), the verdict is `unstable`; the numbers are
  not used for a performance claim.
- A timeout is a failed run: kill the process group, record the failure, carry
  no sample for that invocation, and set the verdict `invalid`. The artifact is
  still written; a silent abort is not acceptable.
- The setup baseline (`K = 0`) is run once per implementation before the
  measured rounds; record `setup_ns` and `setup_fraction`. It is diagnostic,
  not subtracted.
- `K` is chosen so that `setup_fraction <= 0.10` for a micro claim. Increase
  `K` until that holds; record the value in the manifest. Do not change
  `max_cv` to make a noisy run pass.

### F7. Artifact

- One JSON file per experiment, validated against
  `schemas/result.schema.json`.
- It contains experiment metadata, one entry per implementation, raw samples,
  the per-implementation setup baseline, comparisons and a verdict.
- `harness` is language-neutral: required `name` and `version`, optional
  `runtime` (for example `moon 0.1.20261016 / native`). The legacy `python`
  field remains optional for old artifacts but is not written by the MoonBit
  core.
- `comparisons` contain `ratio` and `delta_pct` only between valid
  implementations of the same experiment. A ratio below 1 means the subject is
  faster. No cross-experiment or cross-machine comparison.
- The artifact is never hand-edited. A correction is a rerun.

### F8. Report

- Markdown generated from the artifact only.
- Contains: workload and version, tier, verdict, research question,
  environment, dataset, correctness table, measurement settings, per-
  implementation sample summary, raw samples, comparison, setup fraction,
  verdict notes and reproduction command.
- Every number is accompanied by its tier and workload version.
- A report without an artifact is not accepted; a hand-edited report is not
  accepted.

### F9. Reproduction

- The artifact records a `reproduce_command` with no absolute local paths.
- A clean checkout plus the recorded toolchains can rebuild, regenerate the
  dataset, verify the hash and rerun the experiment.
- Same-host acceptance: same correctness result, `ok` verdict, medians within
  ±5 % of the artifact. A larger difference is an environment/host change and
  must be explained before the result is used.
- Cross-machine reproduction is directional only; absolute times are not
  comparable.

## Numeric Scan, the first workload

| Item | MVP value |
| --- | --- |
| Tier | `micro` |
| Dataset | `uniform-f64`, 1,000,000 elements, seed 20261020, `min=-1.0`, `max=1.0` |
| Input | Raw little-endian `f64`, no header, 8,000,000 bytes |
| Kernel | One sequential pass: `sum`, `sumsq`, `min`, `max`, count above `threshold` |
| Params | `threshold=0.0` |
| Output | `n`, `sum`, `sumsq`, `min`, `max`, `count_above` |
| Reference | Rust |
| Verification | tolerance `rtol=1e-9`, `atol=0`; integers exact |
| Implementations | `moonbit`, `rust`; `c` is P2 |
| Measurement | warmup 3, repeats 10, `K` tuned, timeout 120 s, `max_cv` 0.05 |

Fairness rules for this workload:

- Both implementations must materialize the same in-memory representation
  before the kernel: an array of `f64` values, one per element. The current
  Rust reference converts bytes to `Vec<f64>` during load, while the MoonBit
  draft scans raw bytes on every pass. That is not the same setup, and the
  difference must be removed before the comparison is accepted.
- Both must check that the input length is a multiple of 8 and that `n` matches
  the dataset count.
- Both must use the same threshold and the same comparison (`value > threshold`).
- Both must print floats that round-trip; integers must be JSON integers.
- Both must run the released native build; a different build profile is a
  separate implementation id.
- The MoonBit draft currently uses `unsafe_read_uint64_le`; either keep it with
  an explicit length check and document it, or switch to a safe accessor. The
  adapter summary must state which one is used.

Fault injection for this workload:

- A fixture implementation skips one element (or returns a stale accumulator).
  It must fail correctness, carry no samples and produce an `invalid` verdict.
- The evidence is recorded in the workload README and exercised by a test.

## Acceptance tests

The MVP is accepted only when all of these pass.

| ID | Test | Expected |
| --- | --- | --- |
| A1 | `moon build --release --target native` and `moon test` | Pass; CLI binary exists |
| A2 | `mpf validate` on the repository | Exit 0; all manifests, adapters and artifacts valid |
| A3 | `mpf run workloads/numeric-scan` from the repo root with no `.data/` and no build outputs | Completes; artifact and report written; `verdict=ok` |
| A4 | A3 artifact | `setup_fraction <= 0.10`; CV of each valid implementation `<= max_cv`; samples count equals `repeats`; dataset SHA matches |
| A5 | Run with Python absent from `PATH` | A3 still completes; no Python import or subprocess |
| A6 | Fault fixture | Correctness fails; no samples; verdict `invalid`; artifact written |
| A7 | Timeout fixture | Process group killed; no orphan process; no samples; verdict `invalid`; artifact written |
| A8 | Build-failure fixture | Recorded; implementation excluded; verdict `invalid` |
| A9 | Missing/mutated output field | Correctness fails with a type/value error |
| A10 | `mpf report artifact.json --out /tmp/report.md` | Byte-identical to the committed report |
| A11 | Python `jsonschema` cross-check of the A3 artifact | Passes |
| A12 | MoonBit validator on a mutated artifact | Rejects with a field-level error |
| A13 | Same-host rerun of A3 | Same correctness verdict; medians within ±5 % |
| A14 | Clean clone + documented setup | A3 reproduces; commit and `dirty=false` recorded |
| A15 | Repository hygiene | No `.data/`, `_build/`, `target/`, `results/tmp/` or scratch artifact tracked |
| A16 | CI | MoonBit, Rust and Python cross-check jobs green; no performance claims |
| A17 | `K = 1` / `K = 10` scaling diagnostic | After setup subtraction, the ratio is near 10; a ratio near 1 fails as optimizer elimination |

Acceptance is not "MoonBit is faster". A valid loss, tie or instability is a
valid outcome.

## Host profile

A precision measurement needs a controlled host:

- bare metal or a dedicated VM; no shared CI runner;
- AC power; `performance` CPU governor; no competing load;
- CPU model, logical CPUs, memory, OS, architecture and governor recorded;
- same host for every implementation in the experiment;
- no profiler, sanitizer or tracing in the measured build.

The current laptop (12th Gen Intel i5-12500H, 16 logical CPUs, CachyOS,
`powersave`) produced CV 7.57 % at `K = 10`, above the 0.05 gate. It is useful
for development and correctness, not for the recorded MVP artifact until the
profile is controlled.

## Reproduction path

1. Install the recorded MoonBit and Rust toolchains; confirm `moon version`
   and `rustc --version`.
2. Clone the repository at the recorded commit; confirm `git status` is clean.
3. Install the harness build dependencies (none beyond the toolchains and the
   POSIX utilities `setsid`, `kill`).
4. Run `moon build --release --target native` for the harness and each
   implementation, or let `mpf run` build them.
5. Run `mpf run workloads/numeric-scan`.
6. Confirm the dataset SHA-256, correctness verdict, `ok` verdict and medians
   within ±5 % of the artifact.
7. If the numbers differ, record the host/environment difference; do not edit
   the artifact.

## Definition of done

- [ ] The MoonBit CLI owns list/validate/run/report and the runtime path has no
      Python.
- [ ] The MoonBit core owns manifest, dataset, host calls, verify, measure,
      artifact and report; the ownership matrix is satisfied.
- [ ] numeric-scan has MoonBit + Rust implementations with identical setup
      semantics and a fault-injection test.
- [ ] A committed `ok` artifact and generated report exist for a recorded host.
- [ ] Timeout kills the process group; no orphan remains.
- [ ] The setup baseline is recorded; `setup_fraction <= 0.10`.
- [ ] The artifact validates with both the MoonBit validator and the Python
      schema cross-check.
- [ ] A clean-environment reproduction succeeds; the docs match the commands.
- [ ] CI is green; commits are incremental and traceable.
- [ ] No performance claim is made that is not backed by an artifact.

## Explicitly out of scope

| Feature | Why it is out |
| --- | --- |
| Web dashboard | It does not make the first measurement more trustworthy; it is a P3/P4 presentation layer. |
| Database | Artifacts are files; a DB adds a service and a schema without an MVP question. |
| Distributed execution | One host, one experiment; distribution changes the measurement model. |
| Automatic parameter search | It multiplies runs before the single-run contract is stable. |
| Automatic bottleneck diagnosis | Attribution needs profilers and human analysis; it is P4. |
| Plugin system | A directory and a contract are enough for MVP; a plugin API is premature. |
| Cross-machine absolute comparison | Absolute nanoseconds are not comparable; only directional ratios with both environments. |
| Leaderboard / aggregate score | The project explicitly rejects a single number per language. |
| Profiler integration | P4; profiling is a separate experiment, not the MVP timing path. |
| Windows / wasm harness | No verified process-group primitive; not the MVP platform. |
| C reference | P2; one reference is enough for the MVP. |
| More workloads | P2; numeric-scan must be trustworthy first. |
| Statistical significance tests | The CV stability gate is the MVP guard; formal hypothesis tests are P3. |
