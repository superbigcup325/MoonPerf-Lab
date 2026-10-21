# moonperf — MoonBit core

**Status:** P1 accepted (2026-10-21). The MoonBit core owns the experiment
loop: dataset, manifest, statistics, host primitive, correctness gate, runner,
artifact, report and CLI. Clean builds, toolchain/build-log metadata, the
shared `f64` load path, optimizer barriers, a median-of-three setup baseline,
timeout-as-invalid-artifact and the K=10/20 scaling diagnostic are in. The
active `numeric-scan v5` artifact is accepted and CI is green.

## Build and test

```bash
moon check --deny-warn --target native
moon test --target native
moon fmt --check
```

CLI commands:

```bash
moon run cli --target native -- list ../workloads
moon run cli --target native -- validate ../workloads
moon run cli --target native -- run ../workloads/numeric-scan \
  --out ../results/tmp/moonbit-run --data-dir ../.data --repo-root ..
```

## Dataset vertical slice

The CLI reads the workload manifest, generates the `uniform-f64` bytes, writes
them and prints the dataset identity as JSON:

```bash
moon run cli --target native -- \
  --manifest ../workloads/numeric-scan/workload.toml \
  --out ../results/tmp/moonbit-dataset.bin
```

For the committed numeric-scan manifest the output is:

```text
{"name":"numeric-scan","generator":"uniform-f64","count":1000000,"seed":20261020,"sha256":"fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2","bytes":8000000}
```

The bytes are identical to the Python generator's output; `cmp` and SHA-256 are
the parity test. The 1,000,000-element golden hash is also a `moon test` case.

### Generators

`core/dataset` owns a registry keyed by generator id: `validate` checks the
parameters while the manifest is parsed, and `generate` produces the bytes.
Four ids exist: `uniform-f64` (the `numeric-scan` input),
`structured-records` (fixed 16-byte key/payload records), `strings` (a
dictionary-encoded string column with a skewed index column) and
`nullable-columns` (an integer column with a validity bitmap), all defined in
protocol §4. Adding one is a branch in the
registry; the manifest parser and the artifact writer do not change. The
dataset cache file name carries a digest of the parameters, so two
configurations cannot silently share bytes.

## Boundaries

- This module owns the experiment model and the framework logic; manifest parsing, dataset generation, statistics and `list`/`validate` are ported.
- Workload implementations stay under `workloads/<name>/implementations/`.
- `core/host` runs one child through `setsid -w`, kills the process group on timeout and reaps the child; the orphan test passes.
- `core/runner` builds, verifies, measures, writes the JSON artifact and renders the report.
- No Python on the runtime path. The Python harness is the oracle.
