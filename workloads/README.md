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
  implementations exist. Correctness is checked before any timing is kept.
- Adding a benchmark means adding a directory here, not editing the harness.

See [`docs/experiment-protocol.md`](../docs/experiment-protocol.md) for the
field-by-field contract and [`docs/ROADMAP.md`](../docs/ROADMAP.md) for the
order in which workloads land.

## Current workloads

| Workload | Tier | Status | Implementations |
| --- | --- | --- | --- |
| [numeric-scan](numeric-scan/) | micro | draft | none yet (P1) |
