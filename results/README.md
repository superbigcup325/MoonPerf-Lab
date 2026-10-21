# Results

This directory holds committed experiment artifacts: the JSON record and the
Markdown report generated from it.

```
results/
  <workload>/
    <YYYYMMDDTHHMMSSZ>-<commit12>.json   raw samples, environment, verdict
    <YYYYMMDDTHHMMSSZ>-<commit12>.md     generated report
  tmp/                                   scratch runs, not committed
```

Rules:

- An artifact is committed only when it validates against
  `schemas/result.schema.json`, carries the full environment and the
  reproduction command, and its correctness gate passed.
- The JSON is the source of truth; the report is regenerated from it.
- A result that cannot be reproduced is not deleted silently — it is superseded
  by a new artifact and the reason is recorded in the report.
- `tmp/` is git-ignored. Nothing in it is evidence.
- A scratch run must use `results/tmp/` (or another git-ignored directory under
  `tmp/`). A directory such as `results/tmp-smoke/` is **not** a valid location:
  `mpf validate` treats every JSON under `results/` except `tmp/` as a
  committed artifact.
- An `invalid` artifact can be kept as local diagnostic evidence, but it is not
  a committed result of record. The results of record are `ok` artifacts from a
  recorded host.

There are two artifacts of record, one per active workload, both `ok` from a
clean tree on the recorded host:

| Artifact | Workload | Medians (ns/iter) | CV |
| --- | --- | --- | --- |
| `numeric-scan/20261021T055715Z-a47130edbf4b.json` | v5, micro | C 1058107, Rust 1042542.5, MoonBit 2228174 | 3.62 / 3.99 / 1.90 % |
| `hash-join/20261021T114656Z-b0ff09ba5b87.json` | v1, component | C 22005496, Rust 24314815, MoonBit 24718417 | 3.24 / 2.70 / 4.16 % |

The earlier `numeric-scan/20261021T053956Z-f1d6607a505a.json` remains valid for
its two implementations (CV 3.26 % Rust / 3.05 % MoonBit), and the v4 artifacts
remain readable. Each number belongs to one workload on one host; they are not
summed, ranked or compared across workloads.
