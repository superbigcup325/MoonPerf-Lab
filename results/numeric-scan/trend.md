# numeric-scan result history

**Generated file — do not edit by hand.** `mpf history` renders it from the committed artifacts; the JSON artifacts remain the source of truth.

4 artifacts on 1 host profile, workload v4, v5.

## linux-x86-64-12th-gen-intel-core-i5-12500h-16c-powersave

| Artifact | Started (UTC) | Commit | Version | Verdict | c (ns) | rust (ns) | moonbit (ns) | max CV |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| `20261021T044955Z-13f88214f2a1` | 2026-10-21T04:49:55Z | `13f88214f2a1` | v4 | ok | - | 991620 | 2198479.5 | 1.5692902496380816 % |
| `20261021T050315Z-9b97abaa17cd` | 2026-10-21T05:03:15Z | `9b97abaa17cd` | v4 | ok | - | 997617.5 | 2214432 | 1.5821469504556496 % |
| `20261021T053956Z-f1d6607a505a` | 2026-10-21T05:39:56Z | `f1d6607a505a` | v5 | ok | - | 1014994.5 | 2221970.5 | 3.257743680330669 % |
| `20261021T055715Z-a47130edbf4b` | 2026-10-21T05:57:15Z | `a47130edbf4b` | v5 | ok | 1058107 | 1042542.5 | 2228174 | 3.99182158324879 % |

Each row is one measurement. Rows are comparable only within one host profile and one workload version: a version bump changes the dataset, the parameters or the measurement, so the version column also marks a comparability boundary. Nothing here sums or ranks across workloads, and a delta without its noise model is not a regression.
