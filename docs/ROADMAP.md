# Roadmap

**Reviewed:** 2026-10-21. **Status source of truth:** this document plus
[`architecture.md`](architecture.md), [`mvp.md`](mvp.md) and
[`implementation-boundaries.md`](implementation-boundaries.md).

MoonPerf Lab is a reproducible performance research platform for the MoonBit
ecosystem. It starts from cross-language comparison, but the product is a
verifiable experiment loop: baseline → gap → attribution → optimization →
verification. Moonlake is the first real validation case, not the owner of the
project.

The order is deliberate: **prove the experiment is trustworthy before adding
benchmarks, and close one optimization loop before building a general
platform.** A phase is done when its exit criteria are met with artifacts in
this repository, not when its tasks are ticked off.

The central correction in this revision: the framework core must be MoonBit.
The current Python harness is a bootstrap and a test oracle, not the target
architecture. The MVP is therefore larger than the old plan: it includes the
port of the experiment loop to MoonBit, not only a numeric-scan run.

How to read this revision: positioning and principles are in `README.md`; the
target architecture and verified capabilities are in `architecture.md`; the
MVP contract and acceptance tests are in `mvp.md`; the placement rules are in
`implementation-boundaries.md`; this file owns the phases, current status,
gaps, risks, estimates and the first task.

## At a glance

| Phase | Outcome | Status (2026-10-21) | Estimate (one developer) |
| --- | --- | --- | --- |
| **P0 · Audit, feasibility, contract** | Verified capabilities, consistent docs, frozen experiment contract | In place, this revision | 2–3 days (mostly done) |
| **P1 · Trustworthy MVP** | One reproducible cross-language experiment owned by a MoonBit core | **Accepted (2026-10-21)**; A1–A17 green | 4–5 weeks |
| **P2 · Representative coverage** | A small suite of compute and data-processing workloads | **Accepted (2026-10-21)**; P2.0–P2.5 done | 3–5 weeks |
| **P3 · History, CI, regressions** | Continuous tracking and noise-aware regression detection | Not started | 2–3 weeks |
| **P4 · Profiling and reuse** | Bottleneck attribution and cross-project adoption | Not started; no deadline | 6–10+ weeks |

Estimates assume one developer with the toolchains installed, a working
Moonlake checkout for P2+, a controlled measurement host and AI assistance.
They are ranges, not commitments. The old P1 estimate of 1–2 weeks assumed a Python
runner; it is no longer valid because the core has to be MoonBit.

## Current status

Legend: **implemented** = works and is tested; **partial** = exists but is not
accepted; **not started** = no code; **needs verification** = a claim or
dependency that has not been proven on this toolchain.

| Area | State | Evidence | Gap |
| --- | --- | --- | --- |
| Experiment protocol and schemas | Implemented | `docs/experiment-protocol.md`, `schemas/*.json` | None; the generator interface is specified in §4 |
| Workload manifest and adapter contract | Implemented | `workloads/numeric-scan/workload.toml` v5; `mpf validate` | `status = active`; accepted artifact |
| Python bootstrap: list/validate | Implemented | `mpf list`, `mpf validate`; 57 tests | Not the target core |
| Python bootstrap: run/report | Oracle | `mpf/runner.py`, `mpf/report.py`, `mpf/dataset.py` | Independent cross-check; not the runtime |
| MoonBit implementation of numeric-scan | Implemented | `workloads/numeric-scan/implementations/moonbit/` | None; active and timed in two artifacts |
| Rust reference implementation | Implemented | `workloads/numeric-scan/implementations/rust/` | None; the correctness reference |
| C reference for numeric-scan | Implemented | `workloads/numeric-scan/implementations/c/`; `c-reference` CI job; cross-check script | None |
| Hash-join workload | Implemented | `workloads/hash-join/` v1 active; three implementations; `results/hash-join/20261021T114656Z-b0ff09ba5b87.json`; fault evidence in the README | None |
| Gather workload | Implemented | `workloads/gather/` v1 active; three implementations; `results/gather/20261021T140344Z-b6d5f9215963.json`; fault evidence in the README | None |
| SQL group-by workload | Implemented | `workloads/sql-groupby/` v1 active; four implementations including moonlake 0.3.1; `results/sql-groupby/20261021T144852Z-58eace17a9f4.json` | None |
| MoonBit framework core | Implemented | dataset, manifest (including the declared input matrix), stats, host, verify, artifact, report, runner and CLI; seven clean-build artifacts validate | None; P3 history work is the next core work |
| Dataset generator parity | Implemented | `moon test` golden SHA + `cmp` against the Python bytes, for all six generators | None |
| Process-group timeout | Implemented in MoonBit | `core/host` uses `setsid -w` + `kill` group; wired into the runner; orphan and timeout fixtures pass | None |
| Measurement setup separation | Implemented | median-of-three `--repeat 0` baseline; `setup.fraction` recorded (3.7 %, 3.5 %, 2.0 % in the latest artifact) | None |
| Controlled measurement host | Partial | `powersave` laptop; every committed `ok` artifact is under the 5 % CV gate (worst 4.16 %) | Still a laptop profile, not a dedicated host; cross-session noise is unmeasured |
| CI | Implemented | Python spec, MoonBit core/adapter, Rust build, C build with a Rust cross-check, report regeneration and the timeout fixture | No performance claims on shared runners (by design) |
| Committed valid artifacts | Implemented | Seven `ok` artifacts: four `numeric-scan`, one each for `hash-join`, `gather` and `sql-groupby` | P3 adds the history index and trend reports |
| Dataset generators | Implemented | Registry in `core/dataset` (`validate`/`generate` by id); six generators with golden hashes on both sides | None |
| Reproducibility docs | Implemented | README quick start; `scripts/reproduce-numeric-scan.sh`; protocol §10; clean-clone record | Keep them current as P2 adds workloads |
| Demo and project history | Implemented | P1 accepted; incremental P2 commits; runnable demo and MoonBit-first ownership matrix | Keep the commit slices reviewable as P2 grows |

### What the audit found

These are the concrete defects that blocked the P1 draft. They are kept as the
record of the P0 audit; P1 closed them and the current status table above is
the live view.

1. **Relative implementation paths.** `mpf/runner.py` passes
   `run.impl.directory / "build.sh"` to `subprocess` while also setting
   `cwd=run.impl.directory`. When the workload is given as a relative path (the
   documented invocation), the script path is resolved against the child's
   working directory and the build fails with
   `cannot start workloads/.../build.sh: No such file or directory`.
   `mpf/specs.py` should resolve implementation directories to absolute paths.
2. **Reference is not verified first.** `mpf/runner.py` iterates implementations
   in discovery order and compares against the reference only if the reference
   has already been processed. `moonbit` sorts before `rust`, so MoonBit is
   excluded with "reference did not pass" even when both outputs are identical.
   The reference must be evaluated before any subject.
3. **No clean build.** `_build` runs `build.sh` without removing `_build/` or
   `target/`. The build durations in the smoke run (15 ms MoonBit, 353 ms Rust)
   show incremental builds, not clean builds. The protocol's "build from clean"
   claim is not met.
4. **Timeout aborts the experiment.** `_require_measurement` raises on a
   timeout, so no artifact is written. The protocol's verdict model expects an
   `invalid` artifact with the failure recorded. Either record it or change the
   protocol; do not leave the behavior ambiguous.
5. **Measurement includes setup.** The sample is `wall_ns / inner_repeats`,
   including process startup and dataset loading. With `K = 10` and a 1M-element
   dataset, setup is not negligible. The MVP adds a `K = 0` baseline, records
   `setup_fraction`, and tunes `K`; it does not silently subtract.
6. **The two implementations do not share setup semantics.** Rust converts the
   byte file to `Vec<f64>` before the kernel; the MoonBit draft scans raw bytes
   on every pass with `unsafe_read_uint64_le`. The kernels are not identical in
   contract. Both must materialize the same `f64` array before the timed loop.
7. **The MoonBit adapter has no length check.** It computes `n = length / 8`
   without checking `length % 8 == 0`; Rust does check. Add the check (and a
   clear error) before the kernel.
8. **The artifact schema is Python-locked.** `schemas/result.schema.json`
   requires `experiment.harness.python`. A MoonBit core has no Python. Replace
   it with `name`, `version`, `runtime`; keep old artifacts readable.
9. **The scratch artifact was in the results path.**
   `results/tmp-smoke/20261020T153021Z-988bb680af1d.json` recorded two build
   failures and was not an admissible artifact. It has been removed; scratch
   runs belong under `results/tmp/`.
10. **The host is noisy.** The recorded host is a 12th Gen i5-12500H on
    `powersave`; the Rust sample set had CV 7.57 % at `K = 10`, above `0.05`.
    Raising `K` to 50 brought the CV to 2.07 % (Rust) and 2.36 % (MoonBit) in a
    dirty-tree oracle run, but that is a diagnostic, not a controlled-host
    result. The MVP still needs a controlled host profile, not a relaxed gate.
11. **The docs are stale.** `README.md`, `AGENTS.md`,
    `workloads/README.md` and `results/README.md` describe a pre-runner state.
    This revision updates them.
12. **CI does not build the subjects.** `.github/workflows/ci.yml` only runs
    Python tests and `mpf validate`; it never invokes `moon` or `rustc`.
13. **Dataset cache mismatches are silently regenerated.** `mpf/dataset.py`
    overwrites an existing `.data/` file when its size or hash differs. A hash
    mismatch can mean the generator, params or cache changed; overwriting it
    hides the evidence. The protocol requires a hard failure for a mismatch
    between an artifact and a regenerated file.
14. **The repeat loop may be optimized away.** Both drafts call a pure `scan`
    function in a `for 0..K` loop with invariant input. A compiler may hoist
    the scan out of the loop, making `K` iterations cost one scan. This is not
    yet verified. The adapter needs a compiler barrier (`Bench::keep`,
    `black_box`, a volatile sink or an equivalent) and a scaling check
    (`K = 10` should cost about 10× `K = 1` for a CPU-bound kernel).

## P0 · Audit, feasibility and experiment contract

**Status:** in place, refreshed by this revision. Most P0 artifacts already
exist; the missing piece was an honest audit and a verified MoonBit capability
matrix.

**Goal:** establish what is true before adding code: the repository state, the
MoonBit capabilities that actually exist, the project's own constraints, and
the contract that makes a result admissible.

**Tasks:**

- Audit the repository against the protocol: manifests, schemas, harness,
  implementations, tests, CI, docs, result artifacts.
- Verify the MoonBit capabilities the core depends on: file system, process
  spawn, timeout, process-group kill, monotonic clock, JSON, TOML,
  concurrency, cross-platform support. Record the probe command, toolchain and
  result; do not infer APIs from the language.
- Write down the project's own constraints — MoonBit-first, auditable history,
  runnable examples, no invented gates — and keep them separate from quality
  signals such as CI or a line-count target.
- Decide the architecture: MoonBit core, Python oracle, Rust reference, C in
  P2, Linux native MVP.
- Define the MVP and its acceptance tests.
- Fix the documentation so it describes the current state and the target state
  separately.
- Remove invalid scratch artifacts from the results path; keep scratch runs
  under `results/tmp/`.

**Deliverables:**

- this roadmap;
- [`architecture.md`](architecture.md), including the capability matrix and
  ADRs;
- [`mvp.md`](mvp.md);
- [`implementation-boundaries.md`](implementation-boundaries.md);
- updated `README.md`, `AGENTS.md`, workload READMEs and results README;
- a clean worktree with no invalid artifact under `results/`.

**Acceptance:**

- Every capability claim in the architecture has a probe result or is marked
  "needs verification".
- Every phase has a goal, tasks, deliverables, acceptance, prerequisites,
  explicit non-goals and an exit condition.
- The docs do not present planned capabilities as implemented.
- The first P1 task is independently verifiable.

**Prerequisites:** repository access; MoonBit, Rust and Python toolchains; the
ability to run short process/timeout probes.

**Not doing in P0:** porting the harness, rewriting the protocol, deleting the
Python bootstrap, implementing the MVP.

**Exit:** this document set is merged and the capability matrix is signed off.

**Estimate:** 2–3 days. Most of it was the audit and the probe; the writing is
the remainder.

## P1 · Trustworthy MVP

**Status:** **accepted 2026-10-21**; A1–A17 green.

**Goal:** one complete, reproducible, MoonBit-owned experiment on
`numeric-scan`, with a correctness gate that can fail, raw samples, environment
metadata, JSON and Markdown, and a second person able to reproduce it.

The full specification and acceptance tests are in [`mvp.md`](mvp.md). This
section is the phase plan.

### P1.0: Freeze the oracle and prove the host

**P1.0-A (first task):**

- Fix the two blocking defects in the Python bootstrap (absolute
  implementation paths; reference-first correctness) and add a regression test
  for each.
- Run the experiment on a controlled host profile and record either an `ok`
  artifact or a documented host-instability verdict. Do not relax `max_cv`,
  remove samples or hide an invalid implementation to get a green artifact.

**P1.0-B (only if needed for the contract):**

- Add a `K = 0` setup baseline diagnostic and a clean-build step to the Python
  scaffold **only to validate the contract**, not to grow the Python
  architecture.
- If the host cannot reach CV ≤ 0.05 with a reasonable `K`, record it as
  unsuitable and move the measurement host; do not relax the gate.
- Freeze `mpf/` after this step. It becomes the oracle for the MoonBit port.

**Deliverable:** a green oracle artifact, or a documented host-instability
verdict; a short note in the roadmap on what was learned.

**P1.0-A result (2026-10-20):** the two fixes are in and covered by regression
tests. A `K = 50` run on the `powersave` host produced an `ok` oracle artifact
under ignored `results/tmp/` (CV 2.07 % Rust, 2.36 % MoonBit). It is not an
artifact of record: the tree is dirty, the build was incremental, the setup
baseline and optimizer-elimination checks are not implemented, and the two
implementations still differ in setup semantics. It is enough to validate the
contract and proceed to P1.1.

**Estimate:** 1–2 days.

### P1.1 · MoonBit core skeleton

**P1.1-A (done 2026-10-20):** generate the numeric-scan dataset in MoonBit and
match the recorded SHA-256 byte-for-byte. The CLI parses the real
`workload.toml`, writes the 8,000,000-byte file and prints the identity; `cmp`
and the golden `moon test` both pass.

- Create the `moonperf/` MoonBit module and the `mpf` CLI skeleton.
- Port the manifest model and validation; use the pinned TOML parser.
- Port the dataset generator and SHA-256 identity; prove byte equality with the
  Python generator on the committed manifest.
- Port the typed result model, structural validation, statistics and Markdown
  report.
- Keep the Python implementation as a cross-check: same dataset hash, same
  summary from a fixture, same report from a fixture artifact.

**P1.1-B (done 2026-10-20):** the typed manifest model is ported, including
dataset/verify/measurement parsing and implementation discovery. The MoonBit
CLI now provides `list` and `validate` against the real `workloads/` tree.

**P1.1-C (done 2026-10-20):** summary statistics are ported: count, min,
median, mean, sample standard deviation and CV, with tests for odd/even/single
sample sets.

**Deliverable:** dataset, manifest, statistics and CLI `list`/`validate` are in
place. Report and artifact are still to port; all MoonBit tests pass.

**Estimate:** 5–7 days.

### P1.2 · Host primitive and runner

**P1.2-A (done 2026-10-20):** the MoonBit host primitive runs one child through
`setsid -w`, enforces a timeout, kills the process group on expiry, reaps the
child and returns exit code/wall time/stdout/stderr paths. The orphan test
passes; no `sleep` survives a 200 ms timeout.

**P1.2-B (done 2026-10-20):** the runner orchestration is ported on top of
`core/host`: clean build (using `build_dir`), reference-first correctness,
warmup/repeats, setup baseline, result JSON and the Markdown report. A
clean-build run produced a schema-valid artifact; the host was `unstable`, so
it is not an artifact of record.

- Implement the process primitive with a new process group, timeout,
  process-group kill, exit-code and stdout/stderr capture. Linux MVP:
  `setsid -w` + `kill -KILL -<pid>`; fallback: a small native shim.
- Port the orchestration: build, reference-first correctness, warmup, repeat,
  round-robin, timeout, invalid-artifact recording.
- Add the setup baseline (`K = 0`) and `setup_fraction`.
- Tune `K` for numeric-scan so setup is not dominant.
- Add fixtures: wrong output, timeout with a grandchild, build failure.

**Deliverable:** the MoonBit runner produces a schema-valid artifact and
report; the orphan test passes. Remaining before acceptance: toolchain/build-log
metadata, setup-dominated verdict handling, optimizer-elimination check and a
stable host.

**Estimate:** 5–7 days.

### P1.3 · Numeric-scan fairness and acceptance

**P1.3-A (done 2026-10-20):** both implementations load an `f64` array before
the kernel; MoonBit checks `length % 8 == 0`; both use an optimizer barrier
(`Bench::keep` / `black_box`); the runner performs clean builds via `build_dir`
and records toolchain and build-log SHA-256 in the artifact. The setup baseline
is the median of three runs and is recorded with its run count.

**P1.3-B (done 2026-10-21):** the first `ok` artifact is committed from a
stable-load run (`K=200`, repeats=20, setup median of three). Timeout writes an
`invalid` artifact with `measurement_ok=false` and no samples; the `K = 10` vs
`K = 20` scaling diagnostic is recorded in the verdict notes, and a slope ratio
below 0.5 fails the verdict. CI now runs Python, MoonBit, Rust and the timeout
fixture. A clean clone reproduced an `ok` artifact.

**P1 acceptance status (2026-10-21):**

| Test | Status | Evidence |
| --- | --- | --- |
| A1 build/test all | Pass | Python 57 tests, MoonBit 19 tests, strict check/fmt |
| A2 `mpf validate` | Pass | two committed artifacts validate |
| A3 MoonBit numeric-scan | Pass | `results/numeric-scan/...f1d6607a505a.json` (v5, active) |
| A4 setup/CV gate | Pass | CV 3.26 %/3.05 %, setup 2.6 %/1.5 % |
| A5 no Python runtime | Pass | clean clone ran with MoonBit/Rust only |
| A6 fault injection | Pass | timeout, build-failure and correctness-failure fixtures |
| A7 timeout invalid artifact | Pass | `demo-scan` fixture, `measurement_ok=false` |
| A8 build failure artifact | Pass | `demo-scan` gamma, `build.ok=false` |
| A9 missing field error | Pass | verifier unit test reports the missing field |
| A10 report regeneration | Pass | `mpf report` re-renders the committed Markdown byte-for-byte |
| A11 schema validation | Pass | `mpf validate --result` |
| A12 MoonBit validator | Pass | `validate` command; 19 tests |
| A13 rerun | Pass | three independent artifacts |
| A14 clean clone | Pass | v5 scratch clone run, `dirty=false`, `ok` |
| A15 hygiene | Pass | relative paths only; links checked |
| A16 CI | Pass | [run 39551029540](https://github.com/superbigcup325/MoonPerf-Lab/actions/runs/39551029540) green on `main` |
| A17 scaling diagnostic | Pass | slope ratios 0.96/0.94; fixture check |

P1 is **accepted**: all A1–A17 checks are green, including the remote CI run.

- Make MoonBit and Rust load the dataset into the same `f64` representation
  before the kernel.
- Add the length-multiple-of-8 check and make the unsafe accessor explicit.
- Confirm JSON output types and round-trippable floats.
- Run the full acceptance suite A1–A17 in [`mvp.md`](mvp.md#acceptance-tests).
- Record a committed `ok` artifact and generated report on the controlled host.
- Add fault-injection evidence to the workload README.

**Deliverable:** the first admissible artifact and report, with the fault and
timeout evidence.

**Estimate:** 3–4 days.

### P1.4 · Reproduce, document, retire the bootstrap

- Write the clean-environment reproduction path; test it in a fresh clone.
- Add CI: `moon check`/`moon test`, Rust build, Python schema cross-check,
  spec validation; no performance claims on shared runners.
- Move the Python bootstrap to `tools/legacy-python/` (or keep it clearly
  labelled) and remove it from the runtime path.
- Update the README quick start to the MoonBit CLI.

**Deliverable:** an experiment that runs with Python absent from `PATH`; a
reproduction record; green CI.

**Estimate:** 3–5 days.

### P1 deliverables

- MoonBit core modules and CLI;
- host primitive (utility or shim) with the orphan test;
- MoonBit and Rust numeric-scan implementations with identical setup
  semantics;
- correctness fixtures (wrong output, timeout, build failure);
- one committed `ok` artifact and generated report;
- updated protocol/schema only where the MVP requires it (language-neutral
  harness metadata, setup baseline fields, `--repeat 0` contract);
- reproduction documentation and CI.

### P1 contract changes

These are the only schema/protocol changes P1 needs; they are additive and keep
old artifacts readable.

- `schemas/result.schema.json`: `experiment.harness` requires `version`,
  requires either `name` (new) or the legacy `python`, and accepts optional
  `runtime`; each implementation gains an optional `setup` object
  (`inner_repeats = 0`, `wall_ns`, `fraction`, `runs`).
- `schemas/adapter.schema.json`: optional `build_dir` for the clean-build rule.
- `experiment-protocol.md` §5: `run.sh --repeat 0` is the setup baseline.
- `experiment-protocol.md` §6: the reference is verified first.
- `experiment-protocol.md` §7: record the setup baseline, its fraction and the
  `K = 10` / `K = 20` slope diagnostic; do not subtract the baseline from the
  recorded sample.
- No change to the meaning of raw samples, medians, comparisons or verdicts.

### P1 acceptance

All acceptance tests in [`mvp.md`](mvp.md#acceptance-tests) pass, plus:

- the MoonBit core owns every capability in the ownership matrix;
- the runtime path has no Python;
- a timeout leaves no orphan process;
- `setup_fraction <= 0.10` for the recorded micro artifact;
- the artifact is validated independently by the MoonBit validator and the
  Python `jsonschema` cross-check;
- a second person reproduces the same verdict and medians within ±5 % on the
  same host;
- commits are incremental and traceable.

### P1 prerequisites

- P0 docs merged.
- MoonBit toolchain (pin a version), Rust, a C compiler, `setsid` and `kill`.
- A controlled measurement host.
- The protocol/schema additions agreed before the artifact is recorded.
- A working Moonlake checkout is **not** required for P1.

### P1 not doing

- C reference; more workloads; Moonlake integration;
- web dashboard, database, distributed execution;
- automatic parameter search or bottleneck diagnosis;
- profiler integration;
- Windows/wasm harness;
- leaderboard, aggregate score, cross-machine absolute comparison;
- statistical significance beyond the CV gate;
- a plugin system.

### P1 exit

The MVP is accepted and the next phase can start when the artifact, the
reproduction record and the MoonBit ownership matrix are all in place. "The
code compiles" is not an exit.

**Estimate:** 4–5 weeks total (sum of P1.0–P1.4), assuming a controlled host and
familiarity with MoonBit. Part-time or first-time MoonBit work should plan
6–8 weeks. If time is short, deliver P1.0–P1.3 first; P1.4 can follow.

## P2 · Representative compute and data-processing workloads

**Status:** **accepted 2026-10-21.** P2.0–P2.5 are done.

**Goal:** grow from one calibrated kernel to a small, representative suite that
can explain Moonlake-like data-processing performance without becoming a
benchmark zoo.

Work is sliced so that every step is independently verifiable and lands as its
own commit slice.

### P2.0 · C reference for numeric-scan

**Status:** **done 2026-10-21.**

- The C17 adapter lives in `workloads/numeric-scan/implementations/c/` and
  shares the setup semantics: a multiple-of-8 check, a portable little-endian
  load into one `double` per input, one pass over the array, and an empty-asm
  memory barrier across the repeat loop. The build profile
  (`cc -std=c17 -O3 -march=native`) is part of the implementation id.
- It was added by creating a directory, not by editing the core — the first
  evidence for the "new implementation without touching the framework" rule.
- `scripts/crosscheck-workload.py` runs both adapters on the harness
  dataset and applies the workload's own tolerance rule. The gate was shown to
  fail: a C kernel that starts at element 1 moves `sum` by `0.33` against a
  `7.5e-7` limit. The new `c-reference` CI job builds both adapters and runs
  the cross-check.
- Artifact of record: `results/numeric-scan/20261021T055715Z-a47130edbf4b.json`
  (`verdict=ok`, clean tree, three implementations). C 1058107 ns, Rust
  1042542.5 ns, MoonBit 2228174 ns per iteration; CV 3.62 %, 3.99 %, 1.90 %;
  setup fractions 3.7 %, 3.5 %, 2.0 %; `K=10 -> 20` slope ratios 0.99, 1.14,
  0.97. C and Rust agree within 1.5 %, which is inside the sample CV: the
  compiler check adds no gap of its own.

### P2.1 · Generator interface, generators, template

**Status:** **done 2026-10-21.**

- **Done: the generator interface.** `core/dataset` owns a registry
  (`validate` + `generate`) keyed by generator id, and the manifest carries
  `[dataset.params]` as a generic scalar map instead of hard-coded
  `min`/`max`. Adding a generator is a branch in the registry plus a manifest
  that selects it; the manifest parser and the artifact writer stay agnostic.
- **Done: `structured-records`.** A flat 16-byte record stream (little-endian
  `u64` key then `u64` payload), defined in protocol §4 with a golden SHA-256.
  It is the input the hash-join and gather workloads will use.
- **Done: `strings`.** A dictionary-encoded string column: dictionary of ASCII
  values, then one `skew`-biased index per row, with its own golden SHA-256. It
  is the input for a string join, a dictionary decode or a gather on string
  keys.
- **Done: `nullable-columns`.** An integer column plus an Arrow-style validity
  bitmap (bit set = valid; a null slot carries zero so a reader that ignores
  the bitmap fails its checksum), with its own golden SHA-256.
- **Done: parity.** An independent Python reference in
  `tests/reference_generators.py` reproduces the same bytes, and both sides
  assert the same golden hashes: `moon test` and 63 Python tests pass. The
  uniform-f64 golden hash is unchanged, so the refactor did not touch a
  published dataset.
- **Done: parameter-scoped dataset cache.** The cache file name includes a
  digest of the parameters, so two configurations cannot silently reuse each
  other's bytes.
- **Done: the authoring guide and the template.** `docs/workload-authoring.md`
  is the checklist from question to committed artifact, and
  `workloads/_template/` is a copyable scaffold (manifest, README, one
  placeholder adapter). Every template file carries a `.sample` suffix, so an
  unfinished workload never appears in `mpf list`, `mpf validate` or the
  MoonBit validator.

P2.1 is complete: four generators with two-sided golden hashes, the interface
in protocol §4, and the template. A new workload is now a manifest, a
generator id and adapters.

**Deliverable:** four generators with golden hashes, protocol text for the
interface, the authoring guide and the template — all in place.

### P2.2 · Hash join (component)

**Status:** **done 2026-10-21.**

- `workloads/hash-join/` v1 is active. The input is one `structured-records`
  stream: the first half is the build side, the second half is the probe side,
  and an adapter must reject an odd record count. The split is by position,
  documented in the workload README, so no new generator was needed.
- The output is `build_rows`, `probe_rows`, `pairs` and a 16-hex-digit
  `checksum` of `sum(build_payload + probe_payload)` over every matching pair
  modulo 2^64. The checksum is a pure function of the data — order-independent
  — so implementations can pick their table shape and still have to agree.
- Rust, MoonBit and C implement the same chained-table strategy (64-bit slot
  indices, load factor ≤ 0.5) over one flat `u64` array; all three produce
  `pairs 238491` and `checksum 00000037817646df`.
- Fault injection is recorded, not promised: dropping the build payload from
  the checksum keeps the counters right and changes only the checksum; dropping
  every 1000th build row changes both. A third attempt (skipping just the last
  build row) changed nothing, which is why the evidence is a table, not one
  example.
- Artifact:
  `results/hash-join/20261021T114656Z-b0ff09ba5b87.json` — `ok`, clean tree.
  C 22.0 ms/iter (CV 3.24 %), Rust 24.3 ms (CV 2.70 %), MoonBit 24.7 ms
  (CV 4.16 %); setup fractions 2.7/1.7/2.0 %; slope ratios 1.04/1.11/0.97.
- The result the suite exists for: on this memory-access-bound kernel MoonBit
  is within 1.7 % of Rust, while the compute-bound `numeric-scan` kernel is
  2.14× Rust. One workload on one host is not a language verdict, but it says
  the gap is kernel-specific — exactly the question the component tier adds.
- The oracle needed one fix to support this: it now validates generator ids it
  does not implement and only generates `uniform-f64`, and CI runs the MoonBit
  validator for the per-generator rules.

### P2.3 · Columnar gather (component)

**Status:** **done 2026-10-21.**

- New generator `columnar-gather`: a dense `i64` value column plus a `u32`
  index vector, drawn in runs of `locality` rows, so one parameter moves the
  gather between random and prefetch-friendly. Golden hash, two-sided parity
  and the protocol text are in place; the oracle learned the id without
  gaining the generator.
- `workloads/gather/` v1: Rust, MoonBit and C parse the header, materialize
  8-byte values and 4-byte indices before the timed loop, gather into one
  output vector allocated once and reused, and checksum with a position weight.
  Fault injection recorded: an off-by-one index and a dropped position weight
  both change the checksum.
- **The hard part was the sample size, not the kernel.** At 1 000 000 rows one
  pass is about 1.5 ms, so a 300–400 ms process spends a measurable share of
  its time in startup and the 12 MB load; on this host that produced 5–15 % CV
  at 200 and at 800 inner repeats, and a cache-resident 250 000-row variant was
  no better, while the compute-bound `numeric-scan` kernel held CV 2 % in the
  same sessions. Relaxing `max_cv` was never an option, so the dataset was
  resized: 4 000 000 rows, about 5 ms per pass, 0.4 s of kernel per sample.
- Artifact:
  `results/gather/20261021T140344Z-b6d5f9215963.json` — `ok`, clean tree,
  harness 0.1.1. C 10 109 469.5 ns/iter (CV 2.05 %), Rust 8 314 058.5 ns
  (CV 3.24 %), MoonBit 16 577 759 ns (CV 2.49 %); setup fractions 5.25 / 5.68 /
  3.69 %; slope ratios 0.89 / 0.99 / 1.01.
- The result worth following up: on a loop that is nothing but dependent
  loads, MoonBit is about 2× the Rust median and C is 1.22× Rust. That is an
  attribution question (P4), not a conclusion this artifact can carry.

### P2.4 · Parquet decode or end-to-end SQL through Moonlake

**Status:** **done 2026-10-21.**

- New generator `csv-records`: a deterministic ASCII table (`id,category,amount`,
  one LF-terminated row per record) with a golden hash and two-sided parity.
  CSV was chosen over Parquet because the harness owns dataset generation and
  a Parquet writer belongs to a library, not to the lab; the end-to-end
  question does not need the binary format.
- `workloads/sql-groupby/` v1 is the first end-to-end workload and the first
  consumer of another project: a 2 000 000-row table and one fixed GROUP BY,
  answered four ways. Rust, C and MoonBit parse the CSV and aggregate into
  dense category tables; the `moonlake` implementation registers the file as a
  CSV scan source in a catalog and runs the SQL text through
  `@moonlake.execute`, so parse, bind, plan and scan are inside the number.
- The adapter depends on the published `superbigcup325/moonlake@0.3.1` from
  mooncakes and nothing else from the project — no forked lab, no private
  internals. A fresh toolchain needs `moon update` once so the registry knows
  the version.
- Fault injection recorded: skipping odd rows and dropping the group weight
  both change the answer.
- Artifact:
  `results/sql-groupby/20261021T144852Z-58eace17a9f4.json` — `ok`, clean tree,
  harness 0.1.1. C 26 532 583 ns/iter (CV 1.27 %), Rust 27 338 584.5 ns
  (3.91 %), MoonBit 29 139 280 ns (1.17 %), moonlake 160 946 952 ns (3.33 %);
  setup fractions 3.44 / 3.18 / 3.73 / 0.69 %.
- Two answers, and the workload README keeps them apart: the hand-written
  pipelines are within about 7 % of each other (MoonBit 1.07× Rust, C 2.9 %
  below), and the engine is 5.9× the Rust median because the parse/plan path is
  inside the measurement. The engine column is not a language comparison.

### P2.5 · Suite conclusions and the input matrix

**Status:** **done 2026-10-21.**

- One small input matrix per workload (sizes × distributions), recorded in the
  manifests; no explosion.
- A note on what the suite can and cannot conclude, and a documented answer to
  "which workload should I measure next?".
- A committed `ok` artifact per active workload on a controlled host.

**Landed:**

- `[matrix.<name>]` is part of the manifest contract (protocol §4): entries
  override `count`, `seed` and/or `dataset.params`, carry `probe` or `rejected`
  status with a one-line reason, stay legal datasets of the same generator and
  must differ from the recorded configuration. At most 8; an `active` workload
  declares at least one. The MoonBit core parses and validates them, the schema
  describes them and `mpf validate` enforces the policy.
- `dataset --variant <name>` materializes one entry and prints its identity, so
  an entry is checkable instead of decorative. Nothing sweeps the matrix and no
  variant becomes an artifact of record: the artifact is what one run measured.
- Declared matrices: `numeric-scan` (`all-above`, `tiny`), `hash-join`
  (`few-keys`, `wide-keys`, `small`), `gather` (`scattered`, `sequential`,
  `small`), `sql-groupby` (`many-groups`, `single-group`, `small`). Each
  workload README says what the variant separates; the recorded configuration is
  unchanged, so no version was bumped and every committed artifact stays valid.
- [`suite-conclusions.md`](suite-conclusions.md) states what the four artifacts
  support, what they structurally cannot support, and ranks the candidates for
  the next workload (allocation/strings, a nullable bitmap, threads, an
  explicit SIMD kernel).

**Deliverables:**

- 3–4 active workloads with MoonBit + Rust (and C where useful) references;
- reusable dataset generators with golden identities;
- workload authoring guide and template;
- committed artifacts and reports;
- a short "what the suite can and cannot conclude" note.

**Acceptance:**

- Every active workload has a reference, a fault-injection test, identical
  setup semantics, a tier, a version and a committed `ok` artifact.
- A new workload can be added without editing the MoonBit core.
- Micro/component/e2e results are never summed into a score.
- The suite covers at least one compute-bound, one memory-access-bound and one
  data-processing workload.
- Moonlake can consume at least one result without forking the lab.

**Prerequisites:** P1 stable; C toolchain; controlled host; access to Moonlake
data formats or public APIs; protocol v2 if a new generator/tier requires it.

**Not doing:** P3 automation; P4 profiling; exhaustive operator coverage;
cross-language leaderboard; a general plugin system.

**Exit:** a small suite with reproducible artifacts, and a documented answer to
"which workload should I measure next?"

**Estimate:** 3–5 weeks (P2.0 took about a day; P2.1 is the largest single
slice).

## P3 · History, CI and performance regressions

**Status:** not started.

**Goal:** make the lab a daily development tool: results are tracked over time,
correctness runs on every change, and regressions are detected with a noise
model instead of a hunch.

**Tasks:**

- Keep an append-only result history (files plus a generated index; no
  database).
- Link each artifact to commit, branch, PR, toolchain and host profile.
- Run correctness and schema checks in CI on every PR; build MoonBit and Rust.
- Run performance experiments on a designated host, not a shared CI runner.
- Implement a regression comparison: same workload, same host, baseline
  artifact, a minimum detectable effect derived from CV, and a verdict that
  distinguishes "regression", "noise" and "not comparable".
- Add a trend report per workload.
- Add `mpf run --from-artifact` or an equivalent exact re-run path.
- Measure the false-positive rate over repeated baseline runs.

**Deliverables:**

- history index and trend reports;
- CI workflows for correctness and schema;
- a regression report with a noise model;
- a designated-host runbook;
- re-run command.

**Acceptance:**

- A real regression is detected on the designated host and linked to a commit.
- The false-positive rate is measured over at least 20 baseline runs and is
  documented; a threshold is chosen from data, not intuition.
- CI cannot publish a precision performance claim; it publishes correctness and
  coarse signals only.
- A developer can answer "which workload did this change make faster or
  slower?" from the artifacts.
- Moonlake (or another project) uses the loop in daily development.

**Prerequisites:** P1/P2 artifacts; a stable host; enough history; a CI runner
for correctness; a designated measurement host.

**Not doing:** distributed execution; real-time dashboard; database; automatic
bisect (candidate for later); cross-machine absolute comparison.

**Exit:** regression detection is part of the development loop and its error
rate is known.

**Estimate:** 2–3 weeks.

## P4 · Profiling, attribution and cross-project reuse

**Status:** not started; no deadline.

**Goal:** move from "this is slower" to "this is why, and this change fixes it",
and let other MoonBit projects reuse the lab without forking it.

**Tasks:**

- Integrate existing profilers (`perf`, hardware counters, language-specific
  tools) as separate experiments; do not build a sampling engine.
- Add attribution methods: split a gap into computation, memory access,
  allocation, decoding and runtime overhead; use experiments and profiler
  evidence together.
- Add experiment matrices: build configurations × input sizes × distributions
  × implementation versions; keep the matrix small and recorded.
- Add cross-project adapters: a documented interface for an external project to
  contribute a workload without changing the core.
- Add optimization verification: before/after artifacts, correctness unchanged,
  effect larger than the noise model.
- Publish research reports with an evidence chain.

**Deliverables:**

- profiling recipes and integration notes;
- an attribution report for at least one real gap;
- a cross-project adapter guide and one external integration;
- before/after optimization artifacts;
- a research report template.

**Acceptance:**

- A real bottleneck is attributed with profiler and experimental evidence, not
  a guess.
- An optimization is verified with before/after artifacts and unchanged
  correctness.
- An external MoonBit project integrates one workload without forking the lab.
- The report states what remains unexplained.

**Prerequisites:** P1–P3; profiler availability; an external project; a
controlled host.

**Not doing:** automatic bottleneck diagnosis; an "AI optimizer"; a SaaS;
a distributed cluster; a profiler replacement.

**Exit:** the lab has a repeatable attribution-and-verification loop and at
least one external consumer.

**Estimate:** 6–10+ weeks, open-ended.

## Gap analysis

| Gap | Current (file) | Target | Impact | Action |
| --- | --- | --- | --- | --- |
| Framework language | `mpf/*.py` (Python) | MoonBit `moonperf/` | Fails "MoonBit primary"; duplicate logic risk | Freeze Python; port in slices |
| Harness metadata | `schemas/result.schema.json` requires `harness.python` | `name`, `version`, optional `runtime`; legacy `python` optional | Locks artifacts to Python | Generalize schema; keep old readable |
| Relative paths | `mpf/runner.py` | cwd-independent | Documented `mpf run` fails | Resolve absolute; regression test |
| Reference order | `mpf/runner.py` correctness loop | Reference first | MoonBit always excluded | Evaluate reference first; test |
| Clean build | `mpf/runner.py:_build` | Clean build | Build claim false; timing skewed | Clean temp copy or clean step |
| Timeout artifact | `mpf/runner.py:_require_measurement` | Invalid artifact recorded | No evidence on failure | Record and exit nonzero |
| Measurement setup | `mpf/runner.py` wall/K | Setup baseline + K tuning | Setup contaminates micro results | Add `K=0`; report fraction |
| Setup semantics | Rust `Vec<f64>` vs MoonBit bytes | Same `f64` array | Unfair kernel comparison | Materialize in both |
| Dataset cache mismatch | `mpf/dataset.py` overwrites on mismatch | Hard failure on mismatch | Hides a changed generator/cache | Fail loudly; keep the file |
| Optimizer elimination | `--repeat` loop in MoonBit/Rust drafts | Compiler barrier + scaling check | `K` iterations may measure one scan | Add `black_box`/`keep`; verify the `K=10 -> 20` slope ratio |
| Length check | MoonBit `main.mbt` | `length % 8 == 0` | Crash/UB risk | Add check |
| Process group | Python `start_new_session`; MoonBit no API | Group kill | Orphan processes contaminate next runs | `setsid`/`kill` or shim |
| Host profile | Laptop `powersave`, CV 7.57 % | Controlled profile | No `ok` artifact | Establish profile; rerun |
| Workload status | `status = active` (numeric-scan v5) | `active` after gate | None | Flip only with evidence |
| Scratch artifact | `results/tmp-smoke/` (removed) | No scratch artifact under `results/` | Invalid evidence could enter the results path | Use `results/tmp/`; `results/tmp-*` ignored |
| Docs | README/AGENTS/workloads/results | Current and target separated | Contributors misled | This revision |
| CI | Python only | MoonBit/Rust/correctness | Regressions unseen | Add after core |
| Commits | One commit plus uncommitted P1 work | Incremental traceable | History hard to audit or reproduce | Commit P1 in slices |

## Risk register and verification plan

| Risk | Evidence | Likelihood / impact | Mitigation | Verification | Phase |
| --- | --- | --- | --- | --- | --- |
| MoonBit async is experimental | `moonbitlang/async` README warns API churn; 0.22.5 | Medium / high | Pin version; isolate host calls; upgrade test | Build/test on the pinned version; no API spread beyond `core/host` | P1 |
| MoonBit has no process-group API | Probe: async timeout left two `sleep` processes | Certain / high | `setsid -w` + `kill -KILL -<pid>`; fallback native shim | Orphan test with a grandchild | P1 |
| TOML/SHA/JSON Schema dependencies are immature | Community packages; not all vetted | Medium / medium | Pin; license check; golden tests; fallback in-house | Parse the real manifests; SHA golden; schema cross-check | P1 |
| Short kernels on a shared host | A 1.5 ms gather kernel swung CV 3–22 % at 1M rows regardless of inner repeats, while a compute kernel held 2 % | High / medium | Size the dataset so the kernel dominates the sample (4M rows: 2.0–3.2 % CV); a dedicated host for short kernels | Rerun; compare CV before and after a dataset resize | P2/P3 |
| Porting effort is underestimated | ~1k lines of Python logic + new host primitive + tests | Medium / high | Slice the port; Python oracle; contract tests | Each slice passes a golden/parity test | P1 |
| Semantic drift across languages | Rust `Vec<f64>` vs MoonBit byte scan | High / medium | Same setup representation; shared fixtures; review | Fault injection + byte-identical dataset + output types | P1 |
| Optimizer eliminates the repeated kernel | Unverified `for 0..K` loop with pure `scan` | High / medium | Compiler barrier (`Bench::keep`, `black_box`, volatile sink) | `K=10` vs `K=20` slope test; inspect generated code | P1 |
| Scope creep | Dashboard/DB/auto-diagnosis are attractive | Medium / high | Explicit out-of-scope table; MVP exit gate | PR checklist | P1–P4 |
| Reproducibility depends on network | `moon`/`cargo` registry; toolchains | Medium / medium | Pin versions; record; optional vendor/cache; clean-env test | Fresh clone test with recorded steps | P1 |
| macOS/Windows diverge | `setsid` Linux-only; async supports Linux/macOS | Medium / low | Linux MVP; document unsupported targets | Platform matrix; no claims for untested targets | P1/P2 |
| Dataset parity | Golden SHA and `cmp` passed on 2026-10-20 | Low | Keep the golden test; re-run if the generator or dependency changes | `moon test`; `cmp` | P1 |
| The declared input matrix turns into a benchmark matrix | A declarative list is easy to grow and easy to quote from | Medium / medium | At most 8 entries; a `rejected` entry must say why; variants never become artifacts of record; the suite note states it | `mpf validate`; the manifest schema; review | P2 |
| Invalid artifact reaches results | A scratch artifact was found under `results/` (removed) | Was present / medium | Keep scratch under `results/tmp/`; `results/tmp-*` ignored; validation in CI | Clean tree; CI check | P0 |

## Project principles

The commitments that shape this repository, and where each one is enforced:

1. **MoonBit-first core.** The framework is MoonBit; the programs under test
   may be any language. It is the one rule that shapes the architecture. It is
   qualitative, not a line-count ratio: the answer is a MoonBit core with a
   capability ownership matrix, not padding.
2. **Public repository with an auditable history.** Commit in slices, each one
   explaining its change. A single giant drop is not a development record.
3. **Runnable and reviewable:** a clear README, a runnable example, and tests
   that fail when the code is wrong.
4. **Work that matches the plan.** Scope is argued in this roadmap and in the
   protocol, not added silently.
5. **Open-source compliance:** an OSI-approved license (MIT here), with ported
   or referenced sources attributed.
6. **Explainable research:** the author can explain the goal, the path and the
   quality bar. The architecture, MVP, boundaries and ADRs are that
   explanation.

CI, mooncakes publication, a minimum commit count and a line-count target are
**neither goals nor acceptance criteria**; they are quality signals at most.
The evidence that the project is MoonBit-first is framework ownership and the
tests, not a number of lines.

### Principle-to-evidence mapping

| Principle | Repository evidence | Phase |
| --- | --- | --- |
| MoonBit-first core | MoonBit framework core; capability ownership matrix; `moon test`; CLI built by MoonBit | P1 |
| Auditable history | Incremental P1/P2 commits; no giant drop | P1–P2 |
| Runnable and reviewable | Quick start; `moon run cli -- run workloads/numeric-scan`; MoonBit and Python tests; committed artifact | P1 |
| Work matches the plan | One admissible artifact per active workload, fault injection, reproduction record | P1–P2 |
| Open-source compliance | MIT; dependency licenses recorded; ported/referenced sources attributed | P0/P1 |
| Explainable research | Architecture, MVP, boundaries, ADRs and risk register explain the goal, path and quality | P0 |

## Estimates and assumptions

| Phase | Estimate | Assumption |
| --- | --- | --- |
| P0 | 2–3 days | Audit + probe + docs; most artifacts already existed |
| P1 | 4–5 weeks | One developer, MoonBit familiarity, controlled host, Python oracle reuse |
| P2 | 3–5 weeks | P1 stable; Moonlake formats available; C toolchain |
| P3 | 2–3 weeks | Dedicated host; enough history; CI runner |
| P4 | 6–10+ weeks | Profilers; external project; no deadline |

The old roadmap's P1 estimate (1–2 weeks) assumed a Python runner. The MoonBit
port, the host primitive, the fairness fixes and the acceptance suite are new
work. If time is short, deliver P1.0–P1.3 and defer P1.4.

## Change control

- This document is the planning source of truth; `AGENTS.md` points here and
  does not duplicate phase details.
- The experiment protocol is the normative contract. A semantic change requires
  a protocol version bump and readable old artifacts.
- A workload change to dataset, params, verification or measurement bumps its
  `version`; a published version is immutable.
- A result artifact is never edited. A correction is a rerun.
- A new dependency or a non-MoonBit component requires an ADR entry in
  [`architecture.md`](architecture.md) and a boundary check in
  [`implementation-boundaries.md`](implementation-boundaries.md).

## First verifiable task

**P2 is accepted; the next phase is P3.** The suite answers what P2 promised:
four workloads over the three tiers, a declared input matrix each, a committed
`ok` artifact each, and a written line between kernel-level findings and the
engine-level one. [`suite-conclusions.md`](suite-conclusions.md) is the public
answer to "what can this suite conclude, and which workload should I measure
next?"; P3 starts with the history index and a noise-aware regression verdict,
not with a fifth workload.

The tasks are closed in order: P1.0-A produced a green artifact (2026-10-20),
P1.1-A generated the dataset in MoonBit with matching bytes, P2.0 added the C
reference, P2.1 landed the generator registry plus the authoring guide, P2.2
added the hash join, P2.3 added the gather, P2.4 added the CSV-to-SQL
end-to-end path through moonlake's public interface, and P2.5 declared the
input matrices and closed the phase.

## Plan revision log

- **2026-10-20:** Re-audited the repository; added the MoonBit-first
  architecture, MVP specification and implementation boundaries; corrected the
  phase status, estimates and gaps; added the verified capability matrix, the
  process-group finding and the project principles.
- **2026-10-20 (execution):** fixed the two blocking Python runner defects
  (absolute paths, reference-first) with regression tests; tuned numeric-scan
  to `K=50`; generalized the result harness/setup contract and added
  `build_dir`; added the MoonBit dataset + CLI slice with a passing 1M golden
  hash and byte parity against the Python generator; added the typed manifest
  model, summary statistics, MoonBit `list`/`validate`, the process-group host
  primitive with an orphan test, and the full MoonBit runner/artifact/report.
- **2026-10-21 (P2.4, end-to-end SQL):** added the `csv-records` generator and
  `workloads/sql-groupby/` v1 with four implementations, including the first
  one that consumes another project (moonlake 0.3.1 through a CSV scan source
  and `execute`); recorded the artifact (C 26.5 ms, Rust 27.3 ms, MoonBit
  29.1 ms, moonlake 161.0 ms per iteration) and kept the engine-versus-pipeline
  reading separate from the language comparison.
- **2026-10-21 (P2.3 accepted):** resized the gather dataset to 4 000 000 rows
  after the 1M version could not hold the CV gate on a shared host, recorded the
  `ok` artifact (C 10.1 ms, Rust 8.3 ms, MoonBit 16.6 ms per iteration at
  2.0-3.2 % CV), and made the scaling diagnostic median-of-three after a
  single noisy shot produced a false "optimizer elimination" verdict; the
  harness now records its own version in the artifact.
- **2026-10-21 (P2.3, gather):** added the `columnar-gather` generator and
  `workloads/gather/` v1 with Rust, MoonBit and C implementations and recorded
  fault injection. Four clean-tree runs were `unstable` as the host got busier
  (CV 5–22 %), while a compute kernel on the same host held CV 2.0 %, so the
  workload stays `draft` and the artifact is the next task.
- **2026-10-21 (P2.2, hash join):** added `workloads/hash-join/` v1 with Rust,
  MoonBit and C implementations, an order-independent checksum so the gate
  compares answers rather than algorithms, recorded fault injection, and a
  clean-tree `ok` artifact (C 22.0 ms, Rust 24.3 ms, MoonBit 24.7 ms per
  iteration); taught the oracle to validate generator ids it does not generate
  and added the MoonBit workload validator to CI.
- **2026-10-21 (P2.1 complete):** added `nullable-columns` (values plus a
  validity bitmap) with a two-sided golden hash, wrote
  `docs/workload-authoring.md` and `workloads/_template/`, and closed P2.1; the
  next task is P2.2, the hash join.
- **2026-10-21 (P2.1 generators):** replaced the hard-coded `uniform-f64`
  dataset parameters with a generic `[dataset.params]` map and a generator
  registry in `core/dataset`; added `structured-records` (16-byte key/payload
  records) and `strings` (dictionary plus a skewed index column), each with a
  golden SHA-256 asserted by both `moon test` and an independent Python
  reference; scoped the dataset cache name by a parameter digest; specified the
  interface and both layouts in protocol §4.
- **2026-10-21 (P1 accepted, P2 started):** closed P1 (A1–A17 green, clean-clone
  reproduction, green remote CI); refreshed the status table and the P2 plan;
  added the C17 reference for numeric-scan with the same setup semantics, an
  empty-asm barrier and a recorded build profile; added the C/Rust
  cross-check script and the `c-reference` CI job; recorded the
  three-implementation `ok` artifact
  `20261021T055715Z-a47130edbf4b`; sliced P2 into P2.0–P2.5 with P2.1 as the
  next verifiable task.
- **2026-10-21 (P2.5, accepted — P2 closed):** added the declared input matrix
  to the manifest contract (`[matrix.<name>]` with `probe`/`rejected` status,
  merged dataset overrides, generator-rule checking, at most 8 entries and a
  "must differ from the recorded configuration" rule), enforced by the MoonBit
  core and `mpf validate`; added `dataset --variant <name>` so an entry is
  materializable; declared three entries per workload and wrote
  [`suite-conclusions.md`](suite-conclusions.md) with the cross-workload answer
  and the ranked next-workload list. No recorded dataset changed, so no workload
  version was bumped: the CLI reproduces the committed numeric-scan dataset hash
  byte for byte after the change.

## Documentation change log (2026-10-20)

| File | Change | Reason |
| --- | --- | --- |
| `README.md` | Added MoonBit-first positioning, the project principles, accurate P0/P1 status, target architecture and updated layout/quick start. | The old README described a Python-first pre-runner state and did not state the MoonBit core requirement. |
| `docs/ROADMAP.md` | Rewrote phases P0–P4 with status, tasks, deliverables, acceptance, prerequisites, non-goals, exits and estimates; added audit, gaps, risks, rules basis, first task and this log. | The old plan assumed a Python runner and did not reflect the MoonBit port, the observed defects or the host/process-group risks. |
| `docs/architecture.md` | New: MoonBit-first target architecture, module map, data flow, ownership matrix, verified capability probe, interfaces, measurement model, migration and ADRs. | The repository had no document connecting the positioning to a concrete MoonBit implementation. |
| `docs/mvp.md` | New: MVP definition, scope ladder, functional requirements, numeric-scan spec, acceptance tests, host profile, reproduction path and out-of-scope list. | The old roadmap's MVP was a module list without testable criteria. |
| `docs/implementation-boundaries.md` | New: ownership, host/adapter limits, forbidden duplication, non-MoonBit conditions, dependency policy, platform/tier matrix, interfaces and overhead rules. | Coding agents need actionable placement rules, not abstract principles. |
| `docs/experiment-protocol.md` | Added an implementation-status note; made the harness metadata row language-neutral. | The protocol is normative; readers must not mistake it for an implemented state. No measurement semantics changed. |
| `AGENTS.md` | Added the new documents, MoonBit-first red lines, process-group/setup rules and the frozen-Python policy; corrected status. | The file said there was no runner and listed only Python checks. |
| `workloads/README.md` | Updated workload status/implementations and reference-first/active rules. | The table said "none yet". |
| `workloads/numeric-scan/README.md` | Updated status, implementations, fairness constraints, measurement notes and fault-injection state. | The old README claimed a C implementation and a safe MoonBit loop that the code does not have. |
| `results/README.md` | Added scratch-location and invalid-artifact rules; noted no valid artifact exists. | The invalid smoke artifact sat in the results path. |
| `workloads/numeric-scan/implementations/moonbit/adapter.toml` | Corrected the summary to name `unsafe_read_uint64_le` and the missing length check. | The manifest made a safety claim the code does not support. |
| `.gitignore` | Ignore `results/tmp-*/` as scratch. | Prevent another `tmp-smoke` style directory from being treated as a result. |
| Removed | `results/tmp-smoke/` and the local `.scratch/` probe. | The smoke artifact was invalid evidence; the probe was a temporary capability check. |

## Documentation change log (2026-10-21)

| File | Change | Reason |
| --- | --- | --- |
| `docs/ROADMAP.md` | Marked P2 in progress, sliced it into P2.0–P2.5, recorded the P2.0 evidence, refreshed every stale P1 status row and pointed the first task at P2.1. | P1 was accepted but the status table still described P1 gaps; P2 had no executable plan. |
| `README.md` | Added the P2 status paragraph, corrected the workload/reference rows and removed the C reference from the "deliberately later" list. | The C reference exists now; the status section stopped at P1. |
| `AGENTS.md` | C in the workload layout and in the CI description; still a pointer to the roadmap for progress. | The layout and CI summary were the only P1-era lines left. |
| `workloads/numeric-scan/README.md` | C is an active implementation; fault injection is recorded rather than promised; two artifacts are listed with their medians, CV and setup fractions. | The table said "P2; not an MVP requirement" and the fault fixture was described as missing. |
| `workloads/README.md` | C17 added to the implementation list; two accepted artifacts. | Stale workload table. |
| `results/README.md` | The three-implementation artifact is the artifact of record; the two-implementation artifact remains valid. | The results index pointed only at the earlier artifact. |
| `docs/experiment-protocol.md` | §4 defines the generator registry, the `structured-records` and `strings` layouts and every golden fixture; dataset cache naming is specified. | Three generators exist; the contract has to describe each of them. |
| `moonperf/README.md` | CLI dataset output includes the generator id; a short section describes the registry. | The interface changed and the example output would have been wrong. |
| `docs/workload-authoring.md` | New: the workload checklist from question to committed artifact. | The rules existed across four documents; a contributor had no single path. |
| `workloads/_template/` | New: a copyable scaffold with `.sample` files. | A new workload should not start by re-deriving the layout. |
| `workloads/README.md` | Points at the authoring guide and the template. | The entry point for a new workload. |
