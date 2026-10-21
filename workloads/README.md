# Workloads

Each workload is one directory with a `workload.toml` manifest and, once it is
implemented, an `implementations/` directory with one subdirectory per adapter.

```
workloads/<name>/
  workload.toml          the manifest (dataset, params, verification, measurement)
  README.md              research question and implementation notes (optional)
  implementations/<id>/  adapter.toml, run.sh, optional build.sh / describe.sh
```

Rules:

- The manifest is the contract. Editing the dataset, params, verification or
  measurement means bumping `version`; a published version is never edited in
  place. `schema_version`, `name` and `version` together identify an experiment.
- `status = "draft"` means the workload is specified but not yet measured.
  `active` means every discovered implementation passes the correctness gate.
  `retired` keeps the manifest for history; nothing runs it.
- `verify.reference` names the implementation used as ground truth once
  implementations exist. The reference is verified first; failing it invalidates
  the experiment. Correctness is checked before any timing is kept.
- Adding a benchmark means adding a directory here, not editing the framework
  core. The core is MoonBit; the implementations under test may be any language.
- A workload becomes `active` only after its correctness gate can be shown to
  fail on an injected fault and a valid artifact is recorded.

## Adding a workload

Copy [`_template/`](_template/) and follow
[`docs/workload-authoring.md`](../docs/workload-authoring.md): the template
holds a draft manifest plus one placeholder adapter, and every file is
`.sample` until you rename it, so a half-finished workload never appears in
`mpf list`, `mpf validate` or `moon run cli -- validate`.

The full contract is [`docs/experiment-protocol.md`](../docs/experiment-protocol.md)
(field by field), [`docs/mvp.md`](../docs/mvp.md) (MVP acceptance tests) and
[`docs/ROADMAP.md`](../docs/ROADMAP.md) (the order in which workloads land).

## Current workloads

| Workload | Tier | Status | Implementations |
| --- | --- | --- | --- |
| [numeric-scan](numeric-scan/) | micro | active | MoonBit, Rust, C17 |
| [hash-join](hash-join/) | component | active | MoonBit, Rust, C17 |
| [gather](gather/) | component | draft | MoonBit, Rust, C17 (implemented, artifact pending a quiet host) |

`numeric-scan` and `hash-join` are active with a committed `ok` artifact and
recorded fault-injection evidence; `gather` is implemented and fault-injected
but has no admissible artifact yet, so it is not active. `numeric-scan` asks what a dense floating-point pass
costs; `hash-join` asks what a chained table plus a data-dependent probe costs,
which is the first question the micro tier cannot answer. The Python `mpf run`
draft is not evidence; see the phase status in
[`docs/ROADMAP.md`](../docs/ROADMAP.md#current-status).
