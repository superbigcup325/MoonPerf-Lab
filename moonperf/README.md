# moonperf — MoonBit core

**Status:** P1.1 in progress. The dataset generator and the first CLI slice
exist; the manifest model, report, artifact and runner are still to be ported
from the Python oracle.

## Build and test

```bash
moon check --deny-warn --target native
moon test --target native
moon fmt --check
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
{"name":"numeric-scan","count":1000000,"seed":20261020,"sha256":"fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2","bytes":8000000}
```

The bytes are identical to the Python generator's output; `cmp` and SHA-256 are
the parity test. The 1,000,000-element golden hash is also a `moon test` case.

## Boundaries

- This module owns the experiment model and the framework logic.
- Workload implementations stay under `workloads/<name>/implementations/`.
- Process spawning and timeout are not in this slice yet; they land in P1.2.
- No Python on the runtime path. The Python harness is the oracle.
