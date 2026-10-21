# moonperf-lab — AGENTS.md

## What this is

MoonPerf Lab is a MoonBit-first, reproducible performance research platform:
workload definitions, cross-language experiment infrastructure and verified
optimization evidence. The framework core is MoonBit; the programs under test
may be MoonBit, Rust, C or another language. Moonlake is the first validation
case, not the owner of the project. The project is explicitly **not** a
benchmark collection, a language leaderboard or a profiler replacement.

## Read first

1. [`README.md`](README.md) — positioning, non-goals, status and layout.
2. [`docs/experiment-protocol.md`](docs/experiment-protocol.md) — the
   normative contract for workloads, adapters, measurements and results. Any
   change to a manifest, an adapter or a result goes through this document.
3. [`docs/ROADMAP.md`](docs/ROADMAP.md) — phases, current status, gaps, risks
   and acceptance criteria. Progress belongs there, not here.
4. [`docs/architecture.md`](docs/architecture.md) — MoonBit-first target
   architecture, capability matrix and ADRs.
5. [`docs/mvp.md`](docs/mvp.md) — MVP scope and acceptance tests.
6. [`docs/implementation-boundaries.md`](docs/implementation-boundaries.md) —
   what belongs in MoonBit core, adapters, host scripts and dependencies.

## Layout

```
README.md                    positioning and status
LICENSE                      MIT
docs/experiment-protocol.md  normative experiment contract
docs/ROADMAP.md              phases, status and acceptance
docs/architecture.md         MoonBit-first architecture and capability matrix
docs/mvp.md                  MVP specification and acceptance tests
docs/implementation-boundaries.md  ownership, dependency and platform rules
schemas/workload.schema.json workload manifest contract
schemas/adapter.schema.json  implementation adapter contract
schemas/result.schema.json   experiment result contract
workloads/<name>/            one directory per workload
workloads/numeric-scan/      micro workload; MoonBit, Rust, C17
workloads/hash-join/         component workload; MoonBit, Rust, C17
workloads/_template/         copyable scaffold (not discovered)
moonperf/                    MoonBit core: full experiment loop + CLI (P1 accepted)
mpf/                         Python bootstrap and temporary oracle
host/                        optional native process shim (target; not created)
scripts/                     reproduction scripts
tests/                       unittest suite and runner fixtures
results/                     committed experiment artifacts and reports
```

Adding a workload means adding a directory under `workloads/`; it must not
require editing the framework core. A new language implementation lives under
`workloads/<name>/implementations/<id>/`.

## Build and test

The current Python bootstrap targets Python 3.11+ and has one runtime
dependency (`jsonschema`). It is frozen as an oracle; do not add experiment
features to it.

```bash
uv run mpf list
uv run mpf validate
uv run python -m unittest discover -s tests -v
```

Without uv:

```bash
python3 -m venv .venv
.venv/bin/pip install -e .
.venv/bin/mpf validate
.venv/bin/python -m unittest discover -s tests -v
```

The MoonBit core now owns the full experiment loop. CI runs the Python spec
job, the MoonBit core and adapter checks, the Rust and C adapter builds with a
cross-check of the C output against the Rust reference, and the timeout
fixture. The same authoritative checks run from `moonperf/`:

```bash
cd moonperf
moon check --deny-warn --target native
moon test --target native
moon fmt --check
```

The MoonBit `run` command is the accepted harness for the active workloads:
timeout/scaling handling, report regeneration, clean-clone reproduction and
remote CI are green. The Python `mpf run` draft is only an oracle. Do not
claim, quote or commit a performance result that was not produced by the
accepted harness and recorded as a result artifact.

## Commits and red lines

- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`,
  `perf:`, `chore:`). Commit in reviewable slices; one giant drop is not a
  development record.
- Correctness gates performance: an implementation that fails verification is
  recorded with its errors, carries no samples and is never quoted.
- No aggregate score and no leaderboard. Results are per-workload and
  per-machine, with the environment attached.
- A committed result artifact must validate against
  `schemas/result.schema.json`, contain raw samples, environment metadata and a
  reproduction command. A Markdown report is generated from it, never edited by
  hand.
- Dataset bytes are never committed. They are regenerated into `.data/` from
  `(generator, count, seed, params)` and verified by SHA-256.
- Changing the dataset, params, verification or measurement of a workload bumps
  its `version`; a published version is immutable.
- Changing the meaning of `schemas/` requires bumping `schema_version` and
  keeping old artifacts readable; `mpf validate` and the unit tests must pass.
- MoonBit-first is an architecture rule, not a line-count goal. Experiment
  logic belongs in the MoonBit core; adapters, host scripts and the Python
  oracle must not duplicate it.
- The runtime path must not require Python after P1. Python remains only as a
  cross-check/oracle under `tools/` (or the current `mpf/` until it is moved).
- A timeout must kill the whole process group. A direct-child kill that leaves
  grandchildren alive is a measurement bug, not a slow sample.
- The timed region contains only the child process. Builds, manifest parsing,
  hashing, JSON parsing, statistics and reporting happen outside it. A setup
  baseline is recorded, not silently subtracted. No outlier trimming.
- The harness stays small: no database, service, dashboard or distributed
  execution in the MVP. Add a dependency only with a concrete need, a pinned
  version and a compatible license.
- No absolute local paths, credentials or machine-specific configuration in
  committed files.
