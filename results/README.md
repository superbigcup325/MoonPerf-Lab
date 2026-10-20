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

No artifacts exist yet: the first experiment is the P1 milestone.
