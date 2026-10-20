# Implementation boundaries

**Status:** normative for P1 and later, reviewed 2026-10-20.

This document tells a coding agent where code belongs. When a change is
ambiguous, the default is: put the experiment logic in MoonBit core, keep the
non-MoonBit part as small as possible, and write down the interface and the
test that proves the split.

The target architecture is in [`architecture.md`](architecture.md); the first
deliverable is in [`mvp.md`](mvp.md).

## 1. What the MoonBit core owns

The MoonBit core is the `moonperf/` module (target path; it does not exist yet).
It owns every decision that makes an experiment an experiment:

| Core responsibility | Module | Must not be delegated |
| --- | --- | --- |
| Read and validate `workload.toml` / `adapter.toml` | `core/manifest` | Parsing, defaults, cross-file checks, error messages |
| Generate and hash the dataset | `core/dataset` | Generator algorithm, cache location, SHA-256 identity |
| Decide what is timed | `core/host` + `core/measure` | Timeout, warmup, repeats, process-group kill, sample arithmetic |
| Verify outputs | `core/verify` | Reference selection, exact/tolerance rules, type checks |
| Compute statistics | `core/measure` | Median, mean, stdev, CV, setup fraction |
| Assemble and validate the artifact | `core/artifact` | Field presence, types, verdict derivation |
| Render the report | `core/report` | Every line of Markdown |
| Orchestrate the flow | `core/runner` | Order of build, verify, warmup, measure, write |
| Expose the CLI | `cli` | `list`, `validate`, `run`, `report` |

All core code is MoonBit, built by the MoonBit toolchain. The CLI is a native
MoonBit binary. The experiment path must run with Python absent from `PATH`.

## 2. What a workload implementation owns

An implementation under `workloads/<name>/implementations/<id>/` owns only the
subject of the experiment:

- read the dataset file exactly once per invocation;
- parse the params file;
- run the kernel `K` times, using the result so it cannot be optimized away;
- write the declared output fields as a JSON object;
- exit 0 on success, nonzero on failure;
- print diagnostics to stdout/stderr only (the harness does not parse them).

It does **not** own:

- timing, warmup, sample collection or statistics;
- correctness comparison or verdicts;
- dataset generation, dataset hashing or dataset caching;
- report generation;
- build-profile selection hidden inside `run.sh`;
- any knowledge of another implementation's code or results.

`run.sh` is glue: it must `exec` the built binary, not wrap the measurement in
a shell loop. `build.sh` is glue: it invokes the language toolchain and exits
with its status. A different build profile is a different implementation id,
never a hidden flag. An adapter must stay in its process group: no `setsid`, no
daemonization and no double-fork escape, or the timeout cannot guarantee that
the whole workload is gone.

The implementation may be written in any language. It is the one place where
Rust, C or another language is expected. It is not part of the framework and
does not count as MoonBit core.

## 3. What host scripts and the platform adapter may do

The host boundary exists for OS primitives that MoonBit does not expose. It may
do only the following:

1. **Create a process group/session and run one child.** On Linux MVP:
   `setsid -w <command> ...`. The child is the adapter or the build script.
2. **Kill the process group on timeout, then reap the child.** On Linux MVP:
   `kill -KILL -<pid>` followed by a wait/reap. This is required because a
   direct child kill leaves grandchildren alive; the probe left two `sleep`
   processes behind, and an unreaped child becomes a zombie.
3. **Return raw process facts:** exit code, timed-out flag, wall-clock
   microseconds. No interpretation.
4. **Capture stdout/stderr into files** for the log tail. No parsing of
   experiment output.
5. **Provide OS facts that are not available in MoonBit:** `uname` fields,
   CPU model, memory size, governor. Reading `/proc`, `/sys` and `/etc` is
   acceptable on Linux; the values are recorded as host facts.
6. **Invoke external tools** that are part of the toolchain: `git`, `moon`,
   `rustc`, `cc`. They are recorded in the artifact.

If the `setsid`/`kill` utilities are unavailable, a tiny native shim
(`host/mpf-host.c`, target location) may implement the same contract:
`spawn` with a new process group, `wait`, `kill group`, `clock`, and pipe/file
capture. It must be small, tested against the same orphan test, and must not
contain manifest, verification, statistics, artifact or report logic.

Host scripts must be replaceable: the MoonBit core calls one host interface, and
swapping `setsid` for a C shim must not change any experiment code.

## 4. Logic that must not be duplicated or moved into an adapter

Forbidden in `run.sh`, `build.sh`, a C shim, a Python helper or CI glue:

- parsing/validating `workload.toml` or `adapter.toml`;
- generating or hashing the dataset;
- selecting the reference implementation;
- comparing outputs, applying `rtol`/`atol`, or deciding pass/fail;
- computing medians, means, standard deviations, CV or ratios;
- deciding the verdict (`ok`, `unstable`, `invalid`);
- assembling the result JSON or the Markdown report;
- reading another implementation's output;
- applying per-language special cases in the core;
- hiding a build flag or an input transformation inside an adapter.

A second implementation of a rule is a bug even if it currently agrees. The
only allowed duplicate is the temporary Python oracle used for cross-checking;
it must be labelled `legacy` and must not be on the runtime path.

## 5. Conditions for adding non-MoonBit code

A non-MoonBit addition is allowed only if all of the following hold:

1. The capability is missing from MoonBit stdlib and official MoonBit
   libraries, and the gap is demonstrated by a probe, not assumed.
2. The code is an OS/toolchain boundary, a workload subject, or a temporary
   oracle. It is not experiment logic.
3. The interface is small and documented; the MoonBit side owns the policy.
4. There is a test that fails if the boundary is removed or replaced.
5. The alternative (MoonBit implementation, different library, no feature) and
   its cost are recorded in the PR or the roadmap.

Current allowances:

| Non-MoonBit code | Allowed because | Limits |
| --- | --- | --- |
| Rust/C implementations under `workloads/` | They are the subjects under test. | No experiment logic; separate ids per profile. |
| `setsid` / `kill` utilities | Process-group semantics missing in MoonBit. | Linux MVP; replaceable by a shim. |
| Optional `host/mpf-host.c` | Portable process-group/clock primitive if utilities are insufficient. | No parsing, timing policy, verification or reporting. |
| `git`, `moon`, `rustc`, `cc` | External tools; not framework logic. | Versions recorded; no hidden configuration. |
| Python `mpf/` | Temporary oracle and schema cross-check. | Frozen; no new features; not on runtime path after P1. |
| CI YAML/shell | Orchestrates checks, not experiments. | No performance claims on shared runners. |

Anything else needs a review decision and an ADR entry.

## 6. Dependency policy

Priority order:

1. MoonBit standard library.
2. Official MoonBit libraries (`moonbitlang/*`).
3. A maintained community MoonBit library, pinned to an exact version.
4. A tiny native shim, only for an OS primitive.
5. No Python/Node/service dependency on the runtime path.

Rules:

- Pin exact versions in `moon.mod` and commit the lockfile if the toolchain
  supports it. Record the license; it must be compatible with MIT.
- Add a dependency only with a concrete need and a test that exercises it.
- No network at experiment run time. Dependency and toolchain downloads happen
  during setup/build and are recorded.
- No daemon, database, message queue or hosted service in the MVP.
- A dependency that is experimental (for example `moonbitlang/async`) is
  accepted only with a pinned version, a fallback plan and an upgrade test.
- Prefer a small in-house module over a large dependency when the module is
  testable and the dependency's surface is much larger than the need (for
  example, SHA-256 identity hashing).

Candidate dependencies and status:

| Dependency | Role | Status |
| --- | --- | --- |
| `moonbitlang/async` | fs, process, timeout, pipes | Verified on this host; experimental; pin |
| `moonbit-community/toml` | manifest parsing | Verified on the real manifest; pin |
| `bobzhang/lexer` | transitive TOML dependency | Pin with TOML |
| `moonbitlang/x` | existing adapter file IO | Adapter only; not core |
| SHA-256 package or in-house module | dataset identity | Not yet verified; P1 spike |
| JSON Schema validator or targeted validator | artifact validation | Not yet verified; P1 spike |
| Python `jsonschema` | independent cross-check | Legacy only |

## 7. Backends, operating systems and hardware

The harness is a native CLI. It is not a wasm/JS program and does not run in a
browser.

| Target | Harness | Workloads | Position |
| --- | --- | --- | --- |
| Linux x86_64, native | Supported (MVP) | Supported | Primary platform; `setsid`/`kill` verified |
| Linux aarch64, native | Best effort | Supported | Same POSIX assumptions; not tested in MVP |
| macOS arm64, native | Not MVP | Supported | No `setsid`; needs a native process-group shim |
| Windows x64 | Not supported | Not measured | No verified process-group primitive; not MVP |
| wasm / wasm-gc / JS | Not supported | Not measured | No process spawn; not a measurement host |
| LLVM backend | Not supported | Not measured | Nightly; avoid in MVP |

Hardware rules:

- Compare implementations only on the same host in the same experiment.
- Record CPU model, logical CPUs, memory, OS, governor and architecture.
- The recommended profile is bare metal, AC power, `performance` governor, no
  competing load. The current laptop on `powersave` is not a precision
  instrument; its CV exceeded the gate in the smoke run.
- CPU pinning is not an MVP feature; if added later, record the pinning command.
- Absolute nanoseconds are not comparable across machines. Ratios may be
  directional only, with both environments reported.
- A shared CI runner is adequate for correctness, not for precision
  measurement. Do not quote CI timings as performance results.

## 8. Micro, component and end-to-end tiers

| Tier | Timed region | `inner_repeats` | Primary metric | Setup handling | Allowed claim |
| --- | --- | --- | --- | --- | --- |
| `micro` | One child process with `K` kernel passes | `K >= 10`; tuned so setup is small | `wall_ns / K` | `K = 0` baseline recorded; `setup_fraction` reported | Kernel/compiler cost; only if `setup_fraction <= 0.10` |
| `component` | One operator on realistic data | `K = 1` (or small) | Total wall time | Load and allocation included | Operator cost, layout/allocation effects |
| `end-to-end` | Complete pipeline/query | `K = 1` | Total wall time | I/O and orchestration included | Whole-workload cost |

Rules:

- The tier is recorded in the manifest and in every artifact; it is quoted with
  every number.
- A micro result does not explain a component or end-to-end result on its own.
- Do not compare numbers across tiers. Do not sum tiers into a score.
- For component/end-to-end, the setup is part of the workload; do not subtract
  it and do not claim a kernel-only result.
- For micro, the setup baseline is diagnostic. If it dominates, the artifact is
  labelled and the comparison is not used for a kernel claim.

## 9. Interfaces between execution, collection, analysis and reporting

The pipeline has one direction and one owner per stage:

```text
manifest + implementations
        |
        v
   build records  --(host primitive)-->  build logs, exit codes, durations
        |
        v
   correctness   --(adapter output)---->  values, errors, verdict
        |
        v
   measurement   --(host primitive)---->  raw wall samples + setup baseline
        |
        v
   statistics    --(pure functions)--->   median, mean, stdev, CV, setup fraction
        |
        v
   artifact      --(JSON)------------->   source of truth
        |
        v
   report        --(pure function)---->   Markdown
```

Interface rules:

- **Execution** returns raw facts only: exit code, timed-out flag, wall
  microseconds, log file paths. It never decides pass/fail.
- **Collection** reads the adapter's declared output fields and the raw
  samples. It never changes a sample.
- **Analysis** computes statistics and the verdict from the artifact's data.
  It is a pure function; rerunning it on the same artifact gives the same
  result.
- **Reporting** renders Markdown from the artifact. It never measures and
  never fills a gap with a guess.
- **Validation** checks the artifact against the schema and the semantic rules.
  It does not rewrite the artifact.
- A correction to a number means a new experiment, not a patch of the artifact
  or the report.

## 10. Keeping framework overhead out of the measured program

- The timed region starts immediately before the child spawn and ends when the
  child exits. Manifest parsing, dataset generation, hashing, build, JSON
  parsing, statistics and report rendering happen outside it.
- Builds are never inside the timed region. Build duration and log hash are
  recorded separately.
- The correctness run is separate from the measured run. A failing
  implementation is never timed.
- Warmup runs are discarded and are not samples. Warmup brings the page cache
  and branch predictors to a comparable state.
- Each sample is a fresh process. No state is carried between samples.
- `K` is chosen so the kernel dominates; the setup baseline is recorded and
  reported. Do not silently subtract it.
- The adapter writes its output to a file; the harness parses it after the
  timed region. Do not parse JSON or compute hashes for each sample inside the
  loop.
- Do not run samples in parallel. Parallel samples contend for CPU, memory
  bandwidth and caches.
- Do not attach profilers, sanitizers or tracing to a release measurement run.
  Profiling is a separate experiment with its own record.
- Do not remove outliers. The CV gate decides whether the sample set is stable;
  an unstable set is reported, not trimmed.
- The harness itself should be idle during measurement. No dashboard, no
  background analysis, no parallel experiment.
- Record the governor, CPU model, logical CPUs, memory and any known competing
  load. A measurement without its environment is not admissible.

## Review checklist for a coding agent

Before opening a PR, answer these:

1. Which capability in the ownership matrix does this change touch? Is it in
   the MoonBit core?
2. Does it add experiment logic to an adapter, a host script, a C shim or CI?
   If yes, move it.
3. Does it add a dependency? Is it pinned, licensed and tested? What is the
   fallback?
4. Does it change a manifest, dataset, verification rule or measurement rule?
   If yes, bump the workload `version` and update the protocol/schema.
5. Does it produce or consume an artifact? Does the artifact validate? Is the
   report generated, not edited?
6. Does it change the timed region? If yes, record the change and re-run the
   setup baseline.
7. Does it claim a performance result? Is there an artifact, a host profile, a
   correctness verdict and a reproduction command?
8. Does it leave the repository clean (no build outputs, datasets, scratch
   results, credentials)?

If a rule here conflicts with a concrete need, write the exception in an ADR
and link it from this document. Do not silently break the boundary.
