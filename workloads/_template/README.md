# Workload template

Copy this directory to `workloads/<name>/` and follow
[`docs/workload-authoring.md`](../../docs/workload-authoring.md).

```bash
cp -r workloads/_template workloads/<name>
cd workloads/<name>
for file in $(find . -name '*.sample'); do mv "$file" "${file%.sample}"; done
chmod +x implementations/*/run.sh implementations/*/build.sh implementations/*/describe.sh
```

What to fill in:

1. `workload.toml`: the name must match the directory, then set the tier, the
   dataset, the workload parameters, the compared fields and the measurement.
   Pick a generator id from protocol §4 — do not write a new one for a
   workload.
2. `README.md`: the research question, the dataset identity, the output fields,
   the fault-injection evidence and what would falsify the experiment.
3. `implementations/example/`: rename the directory to the implementation id
   (`moonbit`, `rust`, `c`), set `language` and `summary` in `adapter.toml`,
   and implement `run.sh`. Delete `build.sh` if the implementation needs no
   build step, and fill in `describe.sh` with the toolchain it actually used.

The `.sample` suffix keeps the template out of `mpf list`, `mpf validate` and
`moon run cli -- validate`. Do not commit a `workload.toml` here: a real
workload belongs in its own directory.

Rules that are easy to miss:

- `status = "draft"` until a committed `ok` artifact exists; `active` requires
  every discovered implementation to pass the gate and a fault-injection test.
- Bump `version` whenever the dataset, parameters, verification or measurement
  change; a published version is never edited in place.
- The reference implementation is ground truth and is verified first.
- Keep the setup fraction under the gate and the `K = 10 -> 20` slope near
  linear; a shortcut here invalidates the comparison, not just the run.
