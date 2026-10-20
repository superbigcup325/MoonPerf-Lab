# moonperf-lab — AGENTS.md

## What this is

MoonPerf Lab is a reproducible performance research platform for MoonBit:
workload definitions, cross-language experiment infrastructure and verified
optimization evidence. Moonlake is the first validation case, not the owner of
the project. The project is explicitly **not** a benchmark collection, a
language leaderboard or a profiler replacement.

## Read first

1. [`README.md`](README.md) — positioning, non-goals, status and layout.
2. [`docs/experiment-protocol.md`](docs/experiment-protocol.md) — the normative
   contract for workloads, adapters, measurements and result artifacts. Any
   change to a manifest, an adapter or a result goes through this document.
3. [`docs/ROADMAP.md`](docs/ROADMAP.md) — phases, scope boundaries and
   acceptance criteria. Progress belongs there, not here.

## Layout

```
README.md                    positioning and status
LICENSE                      MIT
docs/experiment-protocol.md  normative experiment contract
docs/ROADMAP.md              phase plan and acceptance criteria
schemas/workload.schema.json workload manifest contract
schemas/adapter.schema.json  implementation adapter contract
schemas/result.schema.json   experiment result contract
workloads/<name>/            one directory per workload
workloads/numeric-scan/      first workload (draft)
mpf/                         Python harness: spec loading and validation
mpf/cli.py                   `mpf list` and `mpf validate`
mpf/specs.py                 schema loading, discovery, cross-file checks
tests/                       unittest suite for the specification
results/                     committed experiment artifacts and reports
```

Adding a workload means adding a directory under `workloads/`; it must not
require editing `mpf/`. A new language implementation lives under
`workloads/<name>/implementations/<id>/`.

## Build and test

The harness targets Python 3.11+ and has one runtime dependency (`jsonschema`).

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

There is no benchmark runner yet (P1). Do not claim, quote or commit a
performance result that was not produced by the harness and recorded as a
result artifact.

## Commits and red lines

- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`,
  `perf:`, `chore:`).
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
- The harness stays small: do not add dependencies without a concrete need;
  `jsonschema` is the only runtime dependency.
- No absolute local paths, credentials or machine-specific configuration in
  committed files.
