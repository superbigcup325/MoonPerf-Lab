# Roadmap

**Reviewed:** 2026-10-20. **Status source of truth:** this document plus
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

| Phase | Outcome | Status (2026-10-20) | Estimate (one developer) |
| --- | --- | --- | --- |
| **P0 · Audit, feasibility, contract** | Verified capabilities, consistent docs, frozen experiment contract | In place, this revision | 2–3 days (mostly done) |
| **P1 · Trustworthy MVP** | One reproducible cross-language experiment owned by a MoonBit core | In progress; P1.0-A, dataset, manifest, stats, host primitive and list/validate are in MoonBit | 4–5 weeks |
| **P2 · Representative coverage** | A small suite of compute and data-processing workloads | Not started | 3–5 weeks |
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
| Experiment protocol and schemas | Implemented | `docs/experiment-protocol.md`, `schemas/*.json` | Result schema still requires a Python `harness.python` field |
| Workload manifest and adapter contract | Implemented | `workloads/numeric-scan/workload.toml`; `mpf validate` | `status = draft`; no accepted run |
| Python bootstrap: list/validate | Implemented | `mpf list`, `mpf validate`; 47 tests | Not the target core |
| Python bootstrap: run/report | Partial | `mpf/runner.py`, `mpf/report.py`, `mpf/dataset.py` | Two blocking defects fixed in P1.0-A; no accepted artifact |
| MoonBit implementation of numeric-scan | Partial | `workloads/numeric-scan/implementations/moonbit/` | Setup semantics differ from Rust; unsafe byte access; no length check |
| Rust reference implementation | Partial | `workloads/numeric-scan/implementations/rust/` | CV above gate on this host; setup semantics differ |
| C reference | Not started | Workload README mentions it | Deferred to P2 |
| MoonBit framework core | Partial | `core/dataset`, `core/manifest`, `core/measure`, `core/host`, `cli`; golden SHA, parity, list/validate, stats, group-kill host | Experiment runner, artifact and report still to port |
| Dataset generator parity | Implemented | `moon test` golden SHA + `cmp` against the Python bytes | Keep the golden test; port the cache/identity path |
| Process-group timeout | Implemented in MoonBit | `core/host` uses `setsid -w` + `kill` group; orphan test passes | Wire it into the experiment runner |
| Measurement setup separation | Partial | `wall_ns // inner_repeats` includes startup/load | Add `--repeat 0` baseline and tune `K` |
| Controlled measurement host | Partial | `K=50` on the `powersave` laptop: CV 2.07 % Rust, 2.36 % MoonBit; `ok` oracle artifact under `results/tmp/` | Still not a controlled profile; setup/clean/hoisting checks pending |
| CI | Partial | Python spec tests only | No MoonBit/Rust build, no correctness fixtures |
| Committed valid artifact | Not started | A dirty-tree `ok` oracle artifact exists under ignored `results/tmp/`; no committed artifact | Produce one accepted `ok` artifact after clean/setup checks |
| Reproducibility docs | Partial | README quick start; protocol §10 | Update after the MoonBit CLI exists |
| Hackathon evidence | Partial | One commit + uncommitted P1 work | Incremental commits, runnable demo, MoonBit-first proof |

### What the audit found

These are the concrete defects that block the current P1 draft. They are the
first tasks, not reasons to rewrite the architecture.

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
MoonBit capabilities that actually exist, the hackathon rules that actually
apply, and the contract that makes a result admissible.

**Tasks:**

- Audit the repository against the protocol: manifests, schemas, harness,
  implementations, tests, CI, docs, result artifacts.
- Verify the MoonBit capabilities the core depends on: file system, process
  spawn, timeout, process-group kill, monotonic clock, JSON, TOML,
  concurrency, cross-platform support. Record the probe command, toolchain and
  result; do not infer APIs from the language.
- Verify the hackathon requirements from the official material. Separate hard
  gates from quality signals. Do not invent a line-count ratio, CI requirement
  or mooncakes requirement.
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

**Status:** in progress as a Python scaffold; not accepted.

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

- Implement the process primitive with a new process group, timeout,
  process-group kill, exit-code and stdout/stderr capture. Linux MVP:
  `setsid -w` + `kill -KILL -<pid>`; fallback: a small native shim.
- Port the orchestration: build, reference-first correctness, warmup, repeat,
  round-robin, timeout, invalid-artifact recording.
- Add the setup baseline (`K = 0`) and `setup_fraction`.
- Tune `K` for numeric-scan so setup is not dominant.
- Add fixtures: wrong output, timeout with a grandchild, build failure.

**Deliverable:** the MoonBit runner produces an artifact comparable to the
Python oracle, and the orphan test passes.

**Estimate:** 5–7 days.

### P1.3 · Numeric-scan fairness and acceptance

- Make MoonBit and Rust load the dataset into the same `f64` representation
  before the kernel.
- Add the length-multiple-of-8 check and make the unsafe accessor explicit.
- Confirm JSON output types and round-trippable floats.
- Run the full acceptance suite A1–A16 in [`mvp.md`](mvp.md#acceptance-tests).
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
  (`inner_repeats = 0`, `wall_ns`, `fraction`).
- `schemas/adapter.schema.json`: optional `build_dir` for the clean-build rule.
- `experiment-protocol.md` §5: `run.sh --repeat 0` is the setup baseline.
- `experiment-protocol.md` §6: the reference is verified first.
- `experiment-protocol.md` §7: record the setup baseline, its fraction and the
  `K = 1` / `K = 10` scaling diagnostic; do not subtract the baseline from the
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
6–8 weeks. If the hackathon deadline is earlier, the deliverable is P1.0–P1.3;
P1.4 can follow.

## P2 · Representative compute and data-processing workloads

**Status:** not started.

**Goal:** grow from one calibrated kernel to a small, representative suite that
can explain Moonlake-like data-processing performance without becoming a
benchmark zoo.

**Tasks:**

- Add a C reference for numeric-scan (compiler comparison; separate id, same
  semantics).
- Add dataset generators for structured records, strings and nullable columns;
  define a small generator interface with hashes and golden bytes.
- Add three workloads, in priority order:
  1. **hash join** (`component`): hash tables, collisions, key distribution,
     match rate;
  2. **columnar gather** (`component`): indirect addressing, layout, cache
     locality;
  3. **Parquet decode** or an **end-to-end SQL** query (`component`/`e2e`),
     selected by what Moonlake can expose without private internals.
- Define a small input matrix per workload (sizes × distributions); do not
  explode the matrix.
- Add a workload authoring guide and a template.
- Record a committed artifact per active workload on a controlled host.
- Integrate one Moonlake-derived workload through a public interface; do not
  couple the lab to Moonlake internals.

**Deliverables:**

- 3–4 active workloads with MoonBit + Rust (and C where useful) references;
- reusable dataset generators;
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

**Estimate:** 3–5 weeks.

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
| Optimizer elimination | `--repeat` loop in MoonBit/Rust drafts | Compiler barrier + scaling check | `K` iterations may measure one scan | Add `black_box`/`keep`; verify `K=1` vs `K=10` |
| Length check | MoonBit `main.mbt` | `length % 8 == 0` | Crash/UB risk | Add check |
| Process group | Python `start_new_session`; MoonBit no API | Group kill | Orphan processes contaminate next runs | `setsid`/`kill` or shim |
| Host profile | Laptop `powersave`, CV 7.57 % | Controlled profile | No `ok` artifact | Establish profile; rerun |
| Workload status | `status = draft` | `active` after gate | No accepted workload | Complete P1; flip after evidence |
| Scratch artifact | `results/tmp-smoke/` (removed) | No scratch artifact under `results/` | Invalid evidence could enter the results path | Use `results/tmp/`; `results/tmp-*` ignored |
| Docs | README/AGENTS/workloads/results | Current and target separated | Contributors misled | This revision |
| CI | Python only | MoonBit/Rust/correctness | Regressions unseen | Add after core |
| Commits | One commit + uncommitted P1 | Incremental traceable | Hackathon criterion at risk | Commit P1 in slices |

## Risk register and verification plan

| Risk | Evidence | Likelihood / impact | Mitigation | Verification | Phase |
| --- | --- | --- | --- | --- | --- |
| MoonBit async is experimental | `moonbitlang/async` README warns API churn; 0.22.5 | Medium / high | Pin version; isolate host calls; upgrade test | Build/test on the pinned version; no API spread beyond `core/host` | P1 |
| MoonBit has no process-group API | Probe: async timeout left two `sleep` processes | Certain / high | `setsid -w` + `kill -KILL -<pid>`; fallback native shim | Orphan test with a grandchild | P1 |
| TOML/SHA/JSON Schema dependencies are immature | Community packages; not all vetted | Medium / medium | Pin; license check; golden tests; fallback in-house | Parse the real manifests; SHA golden; schema cross-check | P1 |
| Measurement host is noisy | CV 7.57 % at `K=10` on `powersave` | High / high | Controlled host profile; tune `K`; CV gate | Rerun; `setup_fraction`; 20-run noise study | P1 |
| Porting effort is underestimated | ~1k lines of Python logic + new host primitive + tests | Medium / high | Slice the port; Python oracle; contract tests | Each slice passes a golden/parity test | P1 |
| Semantic drift across languages | Rust `Vec<f64>` vs MoonBit byte scan | High / medium | Same setup representation; shared fixtures; review | Fault injection + byte-identical dataset + output types | P1 |
| Optimizer eliminates the repeated kernel | Unverified `for 0..K` loop with pure `scan` | High / medium | Compiler barrier (`Bench::keep`, `black_box`, volatile sink) | `K=1` vs `K=10` scaling test; inspect generated code | P1 |
| Scope creep | Dashboard/DB/auto-diagnosis are attractive | Medium / high | Explicit out-of-scope table; MVP exit gate | PR checklist | P1–P4 |
| Hackathon rules change | 2026-09 snapshot; later monthly round may differ | Medium / medium | Cite verified source; re-check the official charter; no invented gates | Read the current charter before submission | P0/P1 |
| Reproducibility depends on network | `moon`/`cargo` registry; toolchains | Medium / medium | Pin versions; record; optional vendor/cache; clean-env test | Fresh clone test with recorded steps | P1 |
| macOS/Windows diverge | `setsid` Linux-only; async supports Linux/macOS | Medium / low | Linux MVP; document unsupported targets | Platform matrix; no claims for untested targets | P1/P2 |
| Dataset parity | Golden SHA and `cmp` passed on 2026-10-20 | Low | Keep the golden test; re-run if the generator or dependency changes | `moon test`; `cmp` | P1 |
| Invalid artifact reaches results | A scratch artifact was found under `results/` (removed) | Was present / medium | Keep scratch under `results/tmp/`; `results/tmp-*` ignored; validation in CI | Clean tree; CI check | P0 |

## Hackathon rule basis

The project is developed for the MoonBit hackathon. The verified rule snapshot
available to this repository is the **2026-09 official material** (archived
2026-09-04, with the deadline extension to 2026-09-30 communicated on
2026-09-22). The formal charter is behind a login wall; the official site says
the formal charter and official notices prevail.

Requirements relevant to this repository, as stated in that material:

1. **MoonBit is the primary implementation language.** This is the only rule
   that changes the architecture. It is a qualitative requirement, not a
   line-count ratio. The correct response is a MoonBit core with a capability
   ownership matrix, not padding.
2. **Public repository with continuous, traceable commits.** Commit the work in
   slices. One giant drop and a single commit are weak evidence.
3. **Runnable project:** clear README, runnable example, necessary tests.
4. **Effective work:** the submission matches its one-page plan; existing
   projects count only the new work.
5. **Open-source compliance:** an OSI-approved license (MIT here), with
   ported or referenced sources attributed.
6. **AI explainability:** the author can explain the goal, path and quality.

Explicitly **not** listed as 2026-09 gates: CI configuration, publishing to
mooncakes, a minimum commit count, or a 4k–10k line target. Treat them as
quality signals, not acceptance criteria. Do not invent a line-count target to
satisfy "MoonBit-first"; the framework ownership and the tests are the evidence.

For a later monthly round, re-verify the current charter and deadlines in the
event group before submission. This roadmap does not assume an October rule
set.

### Acceptance mapping

| Criterion (2026-09 wording) | Repository evidence | Phase |
| --- | --- | --- |
| MoonBit is the primary implementation language | MoonBit framework core; capability ownership matrix; `moon test`; CLI built by MoonBit | P1 |
| Public repository with continuous, traceable commits | Incremental P1 commits; no giant drop | P1 |
| Runnable: clear README, runnable example, tests | Quick start; `mpf run workloads/numeric-scan`; MoonBit + Python tests; demo artifact | P1 |
| Effective work | One admissible artifact, fault injection, reproduction record; existing work counted separately | P1 |
| Open-source compliance | MIT; dependency licenses recorded; ported/referenced sources attributed | P0/P1 |
| AI explainability | Architecture, MVP, boundaries, ADRs and risk register explain the goal, path and quality | P0 |

Quality signals that are **not** gates: CI, mooncakes publication, a minimum
commit count, a 4k–10k line target. They may still be useful; they do not decide
acceptance.

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
work. If the hackathon deadline is earlier, deliver P1.0–P1.3 and defer P1.4.

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

**P1.0-A: make the current oracle produce one green artifact, or prove the host
cannot.** **Status: done 2026-10-20** — see the P1.0-A result above. Fix the
two blocking defects in `mpf/runner.py` (absolute implementation paths;
reference-first correctness), add a regression test for each, run `mpf run` on
a controlled host, and record either an `ok` artifact or a documented
`unstable`/host verdict. This is the first Python work allowed
before the port; it validates the experiment contract, the host profile and the
measurement gate that the MoonBit core must reproduce. The small P1.0-B
contract checks are the only other Python work; the Python architecture is not
extended.

The first **MoonBit** task, P1.1-A, is done: the dataset is generated in
MoonBit, the CLI parses the real manifest, and the bytes and SHA-256 match the
Python generator. The next MoonBit task is the manifest model and the
report/artifact port.

## Plan revision log

- **2026-10-20:** Re-audited the repository; added the MoonBit-first
  architecture, MVP specification and implementation boundaries; corrected the
  phase status, estimates and gaps; added the verified capability matrix, the
  process-group finding and the hackathon rule basis.
- **2026-10-20 (execution):** fixed the two blocking Python runner defects
  (absolute paths, reference-first) with regression tests; tuned numeric-scan
  to `K=50`; generalized the result harness/setup contract and added
  `build_dir`; added the MoonBit dataset + CLI slice with a passing 1M golden
  hash and byte parity against the Python generator; added the typed manifest
  model, summary statistics, MoonBit `list`/`validate` and the process-group
  host primitive with an orphan test.

## Documentation change log (2026-10-20)

| File | Change | Reason |
| --- | --- | --- |
| `README.md` | Added MoonBit-first positioning, hackathon rule context, accurate P0/P1 status, target architecture and updated layout/quick start. | The old README described a Python-first pre-runner state and did not state the MoonBit core requirement. |
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
