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

The first artifact of record is
`results/numeric-scan/20261021T044955Z-13f88214f2a1.json` (numeric-scan v4,
MoonBit core, `verdict=ok`, CV 1.57 % Rust / 1.07 % MoonBit, setup fractions
3.2 % / 1.5 %). It is one workload on one host, not a language ranking. The
invalid smoke attempt from the Python draft was a scratch run and was removed.
