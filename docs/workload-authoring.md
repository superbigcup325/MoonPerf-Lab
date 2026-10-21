# Authoring a workload

A workload is a directory, not a framework change. This guide is the checklist
for adding one: what to decide, what to write, and what evidence makes the
result admissible. The normative rules live in
[`experiment-protocol.md`](experiment-protocol.md); the phase order lives in
[`ROADMAP.md`](ROADMAP.md).

## What you are adding

```
workloads/<name>/
  workload.toml              the contract: dataset, params, verification, measurement
  README.md                  the question, the shape, the fault evidence, the falsifiers
  implementations/<id>/      one adapter per language: adapter.toml, run.sh,
                             optional build.sh / describe.sh
```

The framework core already provides dataset generation, the correctness gate,
the host primitive, statistics, the artifact and the report. If you find
yourself editing `moonperf/core/`, the workload is solving a framework problem
by accident: stop and write the reason in the PR instead.

## Before you start

Answer three questions in writing, because the manifest cannot be written until
they are answered:

1. **Which tier?** `micro` is one kernel on prepared data; `component` is one
   operator including layout and allocation (a hash join, a gather);
   `end-to-end` is a pipeline including I/O and orchestration. A micro result
   never explains an end-to-end result; record the tier and quote it with every
   number.
2. **Which question?** One question per workload, stated in its README. "Is
   MoonBit's hash join slower than Rust's, and is the difference hashing,
   probing or layout?" is a question. "Benchmark everything" is not.
3. **What is the output?** The fields the correctness gate compares. Bulk
   output (a join result, a decoded column) is represented by a checksum field;
   the workload README must define the checksum precisely enough that a second
   implementation can reproduce it.

## Step 1: copy the template

```bash
cp -r workloads/_template workloads/<name>
cd workloads/<name>
for file in $(find . -name '*.sample'); do mv "$file" "${file%.sample}"; done
chmod +x implementations/*/run.sh implementations/*/build.sh implementations/*/describe.sh
```

The template's manifest is a valid `draft`; it is not discovered by `mpf list`
or `mpf validate` until the manifest is named `workload.toml`.

## Step 2: write the manifest

`workloads/numeric-scan/workload.toml` is the worked example. The fields that
matter:

| Field | Rule |
| --- | --- |
| `schema_version` | `1` until the schema itself changes. |
| `name` | Must equal the directory name. |
| `version` | Start at `1`. Bump it whenever the dataset, `params`, verification or measurement change; a published version is never edited in place. |
| `status` | `draft` while it is being built, `active` only when every discovered implementation passes the correctness gate and an `ok` artifact is committed, `retired` when it is kept for history. |
| `tier` | `micro`, `component` or `end-to-end`. |
| `dataset` | `generator`, `count`, `seed` and the generator's own `[dataset.params]`. |
| `params` | Workload parameters handed to every implementation as a sorted `key=value` file. |
| `verify` | `mode`, the compared `fields`, and for tolerance mode `rtol` plus the `reference` implementation id. |
| `measurement` | `warmup`, `repeats`, `timeout_s`, `inner_repeats`, `max_cv`. |

Check it before writing any code:

```bash
mpf validate                                   # schema + adapter + workload rules
cd moonperf && moon run cli --target native -- validate ../workloads
```

## Step 3: pick a dataset

The registry in `core/dataset` owns the generators; a manifest only names one
and supplies its parameters.

| Id | Shape | Use it for |
| --- | --- | --- |
| `uniform-f64` | dense `f64` array | a kernel over prepared numeric data |
| `structured-records` | 16-byte `u64` key + `u64` payload records | joins, scans, group-by over keys |
| `strings` | dictionary-encoded string column with a skewed index column | string joins, dictionary decode, gather on string keys |
| `nullable-columns` | integer column plus a validity bitmap | aggregation or join that must skip nulls |

A new generator is a protocol change, not a workload change: define the layout
in `experiment-protocol.md` §4, add a branch to `validate` and `generate`, and
prove the bytes twice — a golden SHA-256 in `moon test` and an independent
Python reference under `tests/`. The algorithm never changes under a published
id; a new algorithm gets a new id.

## Step 4: implement the adapters

The adapter contract is protocol §5. In short: `run.sh` receives `--input`,
`--params`, `--output` and `--repeat`, runs the kernel `K` times and writes one
JSON object with the declared fields.

The fairness rules are not optional; they are what makes the comparison mean
anything:

- **Same setup representation.** Every implementation materializes the input
  into the same in-memory shape before the timed kernel, on the same data
  layout, with the same arithmetic order.
- **Validate the input.** Check the length, the record count and any padding
  rule before the kernel; a crash is not a slow sample.
- **One barrier across repeats.** A pure kernel over invariant input can be
  hoisted out of `for 0..K`. Use a compiler barrier (`Bench::keep`,
  `std::hint::black_box`, an empty asm with a memory clobber) and keep the
  `K = 10 -> 20` slope check green.
- **No hidden flags.** A different profile, flag or algorithm is a different
  implementation id, never a flag buried in `run.sh`.
- **Round-trippable numbers.** Floats must stay floats in JSON (print enough
  digits to round-trip, never print `1` for `1.0`); integers stay integers.
- **The reference is verified first.** `verify.reference` is ground truth for
  every other implementation and for the fault-injection test.

## Step 5: make the gate able to fail

Correctness gates performance: a failing implementation is recorded with its
errors, carries no samples and is never quoted.

- Use `exact` for integers, strings, booleans and checksums. Use `tolerance`
  only for floating-point fields.
- Inject a fault and prove the gate catches it: skip one element, drop one
  match, ignore a validity bitmap, return a stale accumulator. Record the
  numbers in the workload README (what changed, by how much, against which
  tolerance).
- A reader that ignores a validity bitmap, a padding rule or a checksum field
  must fail, not pass quietly.

## Step 6: measure and record

Run on the recorded host from a clean tree; a dirty tree produces a diagnostic,
not a record:

```bash
cd moonperf
moon run cli --target native -- run ../workloads/<name> \
  --out ../results/tmp/<name> --data-dir ../.data --repo-root ..
```

- Keep `inner_repeats` high enough that the setup fraction stays under the
  tier's gate (`setup_fraction <= 0.10` for micro and component work).
- `max_cv` is a gate, not a suggestion: a run above it is `unstable`, and the
  fix is a quieter host or a larger `K`, never a wider threshold.
- A timeout writes an `invalid` artifact with the failure recorded; it does not
  silently retry.
- An `ok` artifact moves to `results/<name>/` and is committed with its
  generated Markdown report. The report is never edited by hand.

## Step 7: the commit checklist

- [ ] `mpf validate` passes, including the new adapter and the result schema.
- [ ] `moon check --deny-warn`, `moon test`, `moon fmt --check` pass.
- [ ] The workload README states the question, the dataset identity, the
      output fields, the fault-injection evidence and what would falsify the
      experiment.
- [ ] `status = "active"` only with a committed `ok` artifact and a passing
      fault-injection test.
- [ ] The artifact validates, records the environment and contains the raw
      samples, and its report is byte-identical when regenerated.
- [ ] No absolute local paths, no dataset bytes, no machine-specific settings.
- [ ] The commits are slices: the workload, the implementations and the
      artifact are reviewable separately.

## Which workload next

Do not add workloads because they are easy. The order in
[`ROADMAP.md`](ROADMAP.md#p2--representative-compute-and-data-processing-workloads)
is driven by what the suite cannot explain yet: a compute-bound kernel, a
memory-access-bound operator, and one real data-processing path. If a candidate
does not close one of those gaps, it is a benchmark, not a workload.
