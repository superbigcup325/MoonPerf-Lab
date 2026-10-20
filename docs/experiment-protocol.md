# Experiment protocol

**Version 1 (draft).** This document is normative for every experiment recorded
with `schema_version = 1`. A change that alters semantics requires a protocol
version bump; existing artifacts stay readable under the version that produced
them.

> **Implementation status (2026-10-20).** This is the normative contract, not a
> description of the current code. The Python bootstrap implements most of it,
> but no admissible artifact has been produced yet and the MoonBit core is P1.
> The planned P1 additions — a `--repeat 0` setup baseline, reference-first
> verification and language-neutral harness metadata — are specified in
> [`mvp.md`](mvp.md) and [`architecture.md`](architecture.md); they will be
> folded into this protocol when implemented. Until then, version 1 governs.

The protocol exists because a performance number is easy to produce and hard to
trust. It defines what counts as an admissible measurement, so that a result
can be checked by someone who was not present when it was produced.

## 1. Terms and tiers

| Term | Meaning |
| --- | --- |
| **Workload** | A named computation with a canonical dataset, parameters, expected output and verification rules. |
| **Implementation** | One language-specific realization of a workload, identified by its directory name. |
| **Adapter** | The command-line contract between the harness and an implementation. |
| **Sample** | One process invocation timed by the harness, in nanoseconds. |
| **Experiment** | One workload configuration measured across its implementations on one recorded machine. |
| **Result artifact** | The JSON file that records an experiment, including raw samples. The single source of truth. |
| **Report** | Markdown generated from a result artifact. Never hand-edited. |

Tiers describe what a workload measures:

| Tier | Scope | Typical question |
| --- | --- | --- |
| `micro` | A single kernel on prepared data | What does this loop cost, and how do the compilers differ? |
| `component` | One operator on realistic data, including layout and allocation | Where does a hash join or a gather lose time? |
| `end-to-end` | A complete pipeline or query, including I/O and orchestration | What does the whole workload cost? |

A micro result never explains an end-to-end result on its own. The tier is
recorded and quoted with every number.

## 2. What makes a measurement admissible

1. **Correctness gates performance.** Every implementation is verified against
   the reference before it is timed. A failing implementation is recorded in
   the artifact with its errors, carries no samples, and is never quoted as a
   performance result.
2. **Every implementation reads byte-identical input.** The harness generates
   the dataset once and records its SHA-256. Implementations never generate or
   modify the input.
3. **Raw samples are retained.** Means and medians are computed from the
   samples in the artifact; a summary without its samples is not admissible.
4. **The environment is recorded.** The machine, OS, compiler versions, build
   configuration, commit and dataset identity are part of the result. Without
   them the result is not reproducible and not admissible.
5. **Every sample is a fresh process.** No state is carried between samples.
   Warmup runs bring the page cache and branch predictors to a comparable
   state for every implementation before measurement starts.
6. **No hidden configuration.** A different build profile, compiler flag or
   algorithm is a different implementation id. Hiding a flag inside `run.sh`
   invalidates the comparison.
7. **Stability is checked, not assumed.** If the coefficient of variation of
   the samples exceeds `max_cv` (default `0.05`), the verdict is `unstable` and
   no performance claim may be made from that artifact.
8. **No cherry-picking.** Outlier removal is not permitted in version 1. If the
   host produces a bad sample set, the whole experiment is rerun on a fixed
   host and both attempts are kept; the artifact of record is the rerun.
9. **A timeout is mandatory.** Every invocation has one; a timeout is a failed
   run, not a very slow sample.
10. **A result is not a leaderboard.** The artifact reports one workload under
    one configuration. It does not rank languages.

## 3. Repository layout, naming and versions

```
workloads/<name>/
  workload.toml
  README.md                     optional: research question and notes
  implementations/<id>/
    adapter.toml
    run.sh                      required, executable
    build.sh                    optional, runs from a clean checkout
    describe.sh                 optional, prints adapter metadata as JSON
```

- `name` and implementation `id` match
  `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` (kebab-case). Field names in the output
  object use `^[a-z][a-z0-9_]*$` (snake_case).
- A workload moves `draft → active → retired`. `draft` is a specified but
  unmeasured workload. `active` requires at least one implementation and a
  passing correctness gate. `retired` keeps history and is not run.
- **Versioning.** `version` is a positive integer. Bump it whenever the
  dataset, params, verification or measurement rules change. Never edit a
  published version in place; publish a new one. The result records
  `workload.name`, `workload.version` and the manifest SHA-256, so an artifact
  can always be tied to the exact specification.
- **Result location.** Curated artifacts live at
  `results/<workload>/<YYYYMMDDTHHMMSSZ>-<commit12>.json`, with a sibling
  `.md` report generated from it. Ephemeral runs go to `results/tmp/`, which is
  not committed. A result without its companion report is not published.
- **Datasets are never committed.** They are regenerated into `.data/` from the
  manifest and checked by hash.

## 4. Dataset contract

The harness owns data generation. It writes a binary file and records its
SHA-256, byte size and parameters in the result. Implementations only read the
file.

Built-in generators (version 1):

| Id | Element type | Parameters | Layout |
| --- | --- | --- | --- |
| `uniform-f64` | IEEE-754 `f64` | `min`, `max` | Raw little-endian, no header, `count` elements |

`uniform-f64` is defined precisely so that a second implementation of the
harness can reproduce the bytes. With 64-bit unsigned wraparound arithmetic:

```
state = seed
for i in 0..count:
    state += 0x9E3779B97F4A7C15
    z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    z = z ^ (z >> 31)
    u = (z >> 11) * 2^-53
    write_le_f64(min + (max - min) * u)
```

Rules:

- A generator's algorithm never changes under the same id; a different
  algorithm gets a new id (for example `uniform-f64-v2`).
- Dataset identity is `(generator, count, seed, params, sha256)`. A hash
  mismatch between the artifact and a regenerated file is a hard failure.
- Reading the dataset is part of the measured workload and is identical for
  every implementation. It is not excluded from the timing.

## 5. Adapter interface

Each implementation directory contains:

| File | Required | Contract |
| --- | --- | --- |
| `adapter.toml` | yes | `schema_version = 1` and `language`; optional `summary` |
| `run.sh` | yes | Executable; performs one measured invocation |
| `build.sh` | no | Builds from a clean checkout; no arguments; exit 0 means built |
| `describe.sh` | no | Prints a JSON object, e.g. `{"toolchain": "rustc 1.99.0", "notes": "..."}` |

### `run.sh`

```
run.sh --input <dataset-path> --params <params-file> --output <output-json> --repeat <K>
```

- Runs with the implementation directory as the working directory.
- Reads the dataset exactly once, executes the kernel `K` times, and writes the
  output of the last iteration to `--output` as a JSON object.
- Exits 0 on success. Any nonzero exit, crash or timeout fails the run.
- stdout/stderr are diagnostics only; the harness truncates them into the
  result and never parses them.
- Must not access the network, must not read anything outside its directory and
  the given paths, and must not write anywhere except `--output` and temporary
  files inside its own directory.
- Must not cache a previous answer or reuse work across processes. Each process
  starts from zero.

### Output object

- A JSON object with the fields named in `verify.fields`. Extra fields are
  ignored.
- Values are scalars: integer, float, string or boolean. Bulk output (for
  example a join result) is represented by a checksum field; the workload
  documents the checksum function.
- Integers must be encoded as JSON integers and floats as JSON floats; the
  verification is type-aware.
- `NaN` and `Infinity` are not valid JSON and are a failure.
- Floats are printed with enough digits to round-trip (`%.17g`, Rust's default
  formatting, `serde_json`, ...). Truncated output makes tolerance checking
  meaningless.

### Params file

One `key=value` line per workload parameter, sorted by key, UTF-8, no comments,
no blank lines. Values are exactly the scalars declared in `workload.toml`.

### Adapter failure policy

A failed build excludes the implementation from the experiment and marks the
verdict `invalid`; the failure is recorded with its log tail. A failed
correctness check excludes only that implementation from timing and also marks
the verdict `invalid`.

## 6. Correctness verification

Two modes are defined.

**`exact`** — declared fields must match the reference exactly, including JSON
type. Use it for integer, string and boolean outputs, and for checksums. Do not
use it for floating-point results: two valid implementations may differ in the
last bit.

**`tolerance`** — floating-point fields pass when

```
|subject - reference| <= atol + rtol * |reference|
```

while all non-float fields are compared exactly. The workload sets `rtol`
(required) and `atol` (default `0`).

Rules:

- The reference is named by `verify.reference` and must be a discovered
  implementation. The reference defines ground truth; its own output is not
  compared against itself.
- A missing declared field is a failure. Extra fields are ignored.
- Widening `rtol` to make a failing implementation pass is a change to the
  workload: publish a new `version` and explain why in the workload README.
- **Fault injection is part of the workload's acceptance.** Before a workload
  becomes `active`, the author demonstrates that a deliberately wrong
  implementation fails the gate (for example, skipping one element, or
  returning a stale accumulator). The evidence goes in the workload README.

## 7. Measurement

- **Build profile.** Performance experiments use the release profile of each
  toolchain (MoonBit `moon build --release`, Rust `--release`, C `-O3`). A
  debug, instrumented or differently optimized build is a separate
  implementation id; profiles are never mixed inside one table. The exact build
  command is recorded in the artifact, and `describe.sh` records the toolchain
  version.
- **Clock.** Monotonic wall-clock time around the child process, in
  nanoseconds, measured by the harness.
- **Sample.** One process invocation with `--repeat K`, where `K` is
  `measurement.inner_repeats`. The recorded per-iteration time is
  `wall_time / K`. The constant cost of process startup and dataset loading is
  amortized over `K`; it is identical for every implementation in the same
  experiment.
- **Sequence.**
  1. Build every implementation from clean (`build.sh`) and record the result.
  2. Correctness run per implementation; failing implementations are excluded.
  3. `warmup` invocations per implementation, discarded.
  4. `repeats` measurement rounds. Each round runs every implementation once;
     the starting implementation rotates each round (round-robin interleaving),
     so slow drift and thermal effects do not systematically favour one entry.
  5. Record every raw per-iteration sample.
- **Timeout.** `measurement.timeout_s` per invocation. The process group is
  killed on expiry; the sample is a failure and the verdict is `invalid`.
- **No trimming.** All samples go into the artifact. The summary uses the
  median as the comparison metric (robust to a single slow sample) and also
  records min, mean, sample standard deviation and coefficient of variation.
- **Stability gate.** `cv = stdev / mean`. If
  `cv > measurement.max_cv` (default `0.05`), the verdict is `unstable` and the
  numbers are not used for a claim.
- **Host.** Compare only on the same host with the same toolchains. Recommended:
  bare metal, `performance` CPU governor, no competing load, hyperthreading
  state recorded, optional CPU pinning recorded. A shared CI runner is adequate
  for correctness, not for precision measurement.
- **Choice of `K`.** Large enough that the per-iteration constant is
  negligible: `inner_repeats >= 10` for micro workloads. Large datasets that
  already dominate the load time may use `K = 1`; the manifest records the
  choice.

## 8. Metadata

A result artifact is invalid if any of the following is missing:

| Group | Fields |
| --- | --- |
| Source | `commit` (40 hex chars), `dirty`, `branch` |
| Harness | harness `version`, runtime name/version (the current Python bootstrap records the Python version) |
| Workload | `name`, `version`, `tier`, manifest SHA-256 |
| Dataset | `generator`, `count`, `seed`, `params`, SHA-256, byte size |
| Parameters | the workload params used |
| Measurement | `warmup`, `repeats`, `inner_repeats`, `timeout_s`, `max_cv`, `order`, `clock` |
| Environment | OS, OS release, architecture, CPU model, logical CPUs, governor, memory |
| Implementation | id, language, toolchain, build status/command/duration/log hash, correctness verdict |
| Reproduction | the exact command line (`reproduce_command`) |
| Time | `started_at`, `finished_at` in UTC RFC 3339 |

The result JSON is generated by the harness and never hand-edited. A correction
means a rerun, not a patch.

## 9. Result artifact

One JSON file per experiment, validated against
[`schemas/result.schema.json`](../schemas/result.schema.json). It is the source
of truth; the Markdown report is a generated view.

Contents:

- experiment metadata (§8);
- one entry per implementation, including the build record, correctness verdict
  and raw samples;
- `comparisons`: `ratio = subject median / baseline median` and
  `delta_pct = (ratio - 1) * 100`, computed only between two valid
  implementations of the same experiment. A ratio below `1` means the subject
  is faster. The artifact does not compare across experiments or machines; that
  is a P3 capability and needs its own environment check.
- `verdict`: `ok`, `unstable` or `invalid`, with notes explaining the decision.

The Markdown report contains: the research question, the environment, the
correctness table, the per-implementation sample summary and raw sample list,
the comparison table, the verdict and the reproduction command. It states the
tier and the workload version next to every number.

## 10. Reproducing an experiment

To reproduce an artifact:

1. Check out the recorded commit (and note `dirty`).
2. Install the recorded toolchains; run each `build.sh`.
3. Regenerate the dataset from the manifest and confirm its SHA-256 matches the
   artifact.
4. Run the recorded `reproduce_command` on the same host profile.

Acceptance of a same-host reproduction: same correctness result, `ok` verdict,
and medians within ±5% of the original. Larger differences mean the environment
or the host changed and must be explained before the result is used.

Cross-machine reproduction is directional only: absolute nanoseconds are not
comparable, ratios may be, and the environment of both sides must be reported.
"Reproduced" never means bit-identical timings.

## 11. Adding a workload

1. Create `workloads/<name>/workload.toml`; keep `status = "draft"` until the
   gate exists.
2. Choose a built-in dataset generator and parameters; do not invent a dataset
   format inside an implementation.
3. Implement the reference first, then at least one comparison implementation.
4. Declare `verify.mode`, `verify.fields`, `verify.reference` and, in tolerance
   mode, `rtol`.
5. Demonstrate fault detection and record it in the workload README.
6. Run `mpf validate`; every manifest, adapter and script must pass.
7. Run the experiment on the recorded host and commit the result JSON and its
   generated report under `results/`.
8. Flip the workload to `active` only when all of the above holds.

## 12. Versioning and change control

- `schema_version` identifies the document format. An incompatible change bumps
  it; old artifacts remain valid under their own version.
- The protocol version and the schema version move together.
- Workload `version` changes with dataset, params, verification or measurement
  changes, never with implementation-only changes.
- The harness version is recorded in every artifact; a harness change that
  alters measurement semantics is a protocol change.

## 13. Deferred

Version 1 deliberately does not include: a web UI, a database, distributed
execution, automatic parameter search, statistical significance testing beyond
the stability gate, profiler integration or cross-experiment dashboards. Those
belong to later phases and must not leak into the MVP.
