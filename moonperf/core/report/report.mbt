///|
fn line(builder : StringBuilder, text : String) -> Unit {
  builder.write_string(text)
  builder.write_char('\n')
}

///|
fn ns(value : Double) -> String {
  value.to_string()
}

///|
fn pct(value : Double) -> String {
  if value >= 0.0 {
    "+" + value.to_string() + " %"
  } else {
    value.to_string() + " %"
  }
}

///|
fn summary_row(implementation : @artifact.ImplementationRecord) -> String {
  match implementation.summary {
    None => "| `" + implementation.id + "` | - | - | - | - | - | - |"
    Some(summary) =>
      "| `" +
      implementation.id +
      "` | " +
      summary.count.to_string() +
      " | " +
      ns(summary.median_ns) +
      " | " +
      ns(summary.mean_ns) +
      " | " +
      ns(summary.min_ns.to_double()) +
      " | " +
      ns(summary.stdev_ns) +
      " | " +
      (summary.cv * 100.0).to_string() +
      " % |"
  }
}

///|
/// Render the Markdown view of an artifact. The artifact is the source of
/// truth; this function never measures or fills a missing number.
pub fn render(artifact : @artifact.Artifact, question : String) -> String {
  let builder = StringBuilder()
  line(
    builder,
    "# " + artifact.workload_name + " v" + artifact.workload_version.to_string(),
  )
  line(builder, "")
  line(
    builder,
    "**Generated report — do not edit by hand.** It is rendered from the JSON " +
    "artifact; the JSON is the source of truth.",
  )
  line(builder, "")
  line(builder, "| Field | Value |")
  line(builder, "| --- | --- |")
  line(
    builder,
    "| Workload | `" +
    artifact.workload_name +
    "` v" +
    artifact.workload_version.to_string() +
    " |",
  )
  line(builder, "| Tier | `" + artifact.tier + "` |")
  line(builder, "| Verdict | **" + artifact.verdict_status + "** |")
  line(builder, "| Experiment | `" + artifact.id + "` |")
  line(builder, "| Started (UTC) | " + artifact.started_at + " |")
  line(builder, "| Finished (UTC) | " + artifact.finished_at + " |")
  line(builder, "")
  line(builder, "## Research question")
  line(builder, "")
  line(
    builder,
    if question.length() == 0 {
      "_The workload does not declare a research question._"
    } else {
      question
    },
  )
  line(builder, "")
  line(builder, "## Environment")
  line(builder, "")
  line(builder, "| Field | Value |")
  line(builder, "| --- | --- |")
  line(
    builder,
    "| OS | " +
    artifact.environment.os +
    " " +
    artifact.environment.os_release +
    " |",
  )
  line(builder, "| Architecture | " + artifact.environment.arch + " |")
  line(
    builder,
    "| CPU | " +
    artifact.environment.cpu_model +
    " (" +
    artifact.environment.logical_cpus.to_string() +
    " logical CPUs) |",
  )
  line(
    builder,
    "| CPU governor | " +
    artifact.environment.governor.unwrap_or("not recorded") +
    " |",
  )
  line(
    builder,
    "| Memory | " +
    (artifact.environment.memory_bytes / 1073741824L).to_string() +
    " GiB |",
  )
  line(builder, "| Harness | moonperf 0.1.0 on MoonBit native |")
  line(
    builder,
    "| Source | commit `" +
    artifact.source.commit +
    "`" +
    (if artifact.source.dirty { " (dirty)" } else { "" }) +
    " on `" +
    artifact.source.branch +
    "` |",
  )
  line(builder, "")
  line(builder, "## Dataset")
  line(builder, "")
  line(builder, "| Field | Value |")
  line(builder, "| --- | --- |")
  line(builder, "| Generator | `" + artifact.dataset.generator + "` |")
  line(
    builder,
    "| Count | " +
    artifact.dataset.count.to_string() +
    " elements (" +
    artifact.dataset.bytes.to_string() +
    " bytes) |",
  )
  line(builder, "| Seed | " + artifact.dataset.seed.to_string() + " |")
  line(builder, "| SHA-256 | `" + artifact.dataset.sha256 + "` |")
  line(builder, "")
  line(builder, "## Correctness gate")
  line(builder, "")
  line(
    builder, "| Implementation | Language | Passed | Checked against | Notes |",
  )
  line(builder, "| --- | --- | --- | --- | --- |")
  for implementation in artifact.implementations {
    let notes = if implementation.correctness.errors.length() == 0 {
      "ok"
    } else {
      implementation.correctness.errors.join("; ")
    }
    line(
      builder,
      "| `" +
      implementation.id +
      "` | " +
      implementation.language +
      " | " +
      (if implementation.correctness.ok { "yes" } else { "**no**" }) +
      " | " +
      implementation.correctness.checked_against.unwrap_or("reference") +
      " | " +
      notes +
      " |",
    )
  }
  line(builder, "")
  line(builder, "Only implementations that passed this gate are timed.")
  line(builder, "")
  line(builder, "## Measurement")
  line(builder, "")
  line(
    builder,
    "Warmup: " +
    artifact.measurement.warmup.to_string() +
    " invocations per implementation · Repeats: " +
    artifact.measurement.repeats.to_string() +
    " rounds · Inner repeats: " +
    artifact.measurement.inner_repeats.to_string() +
    " · Timeout: " +
    artifact.measurement.timeout_s.to_string() +
    " s · Order: round-robin · Clock: monotonic.",
  )
  line(builder, "")
  line(
    builder, "| Implementation | Samples | Median | Mean | Min | Stddev | CV |",
  )
  line(builder, "| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
  for implementation in artifact.implementations {
    line(builder, summary_row(implementation))
  }
  line(builder, "")
  if artifact.comparisons.length() > 0 {
    line(builder, "## Comparison")
    line(builder, "")
    line(
      builder, "Ratio is subject median divided by baseline median; below 1 means the subject is faster. This is one workload on one host, not a language ranking.",
    )
    line(builder, "")
    line(
      builder, "| Subject | Baseline | Subject median (ns) | Baseline median (ns) | Ratio | Delta |",
    )
    line(builder, "| --- | --- | ---: | ---: | ---: | ---: |")
    for comparison in artifact.comparisons {
      line(
        builder,
        "| `" +
        comparison.subject +
        "` | `" +
        comparison.baseline +
        "` | " +
        ns(comparison.subject_ns) +
        " | " +
        ns(comparison.baseline_ns) +
        " | " +
        comparison.ratio.to_string() +
        " | " +
        pct(comparison.delta_pct) +
        " |",
      )
    }
  } else {
    line(builder, "## Comparison")
    line(builder, "")
    line(
      builder,
      "No comparison is published for this artifact: the verdict is `" +
      artifact.verdict_status +
      "`, so the numbers are not used for a claim.",
    )
  }
  line(builder, "")
  line(builder, "## Raw samples")
  line(builder, "")
  line(builder, "Per-iteration nanoseconds, in measurement order.")
  for implementation in artifact.implementations {
    if implementation.samples_ns.length() > 0 {
      line(builder, "")
      line(
        builder,
        "`" +
        implementation.id +
        "` (" +
        implementation.samples_ns.length().to_string() +
        " samples):",
      )
      line(builder, "")
      let samples = implementation.samples_ns.map(fn(sample) {
        sample.to_string()
      })
      line(builder, "```text")
      line(builder, samples.join(" "))
      line(builder, "```")
    }
  }
  line(builder, "")
  line(builder, "## Verdict")
  line(builder, "")
  line(builder, "**" + artifact.verdict_status + "**")
  if artifact.verdict_notes.length() > 0 {
    line(builder, "")
    for note in artifact.verdict_notes {
      line(builder, "- " + note)
    }
  } else {
    line(builder, "")
    line(builder, "The correctness gate passed and every sample set is stable.")
  }
  line(builder, "")
  line(builder, "## Reproduce")
  line(builder, "")
  line(builder, "```bash")
  line(builder, artifact.reproduce_command)
  line(builder, "```")
  line(builder, "")
  line(
    builder, "Same-host acceptance: identical correctness verdict and medians within ±5 % of this artifact. Cross-machine numbers are directional only.",
  )
  line(builder, "")
  line(builder, "_Generated by `moonperf` from the JSON artifact._")
  builder.to_string()
}
