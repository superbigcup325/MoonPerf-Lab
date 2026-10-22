///|
/// The history is derived data: it never measures and never fills a missing
/// number. Every field here is read from one committed artifact, and the
/// artifact stays the source of truth.
///
/// One implementation's row inside a history entry: the numbers a trend or a
/// regression comparison reads, plus the verdict that says whether they may be
/// quoted at all.
pub struct ImplementationPoint {
  id : String
  language : String
  reference : Bool
  median_ns : Double?
  cv : Double?
  samples : Int32
  correctness_ok : Bool
}

///|
/// One committed artifact reduced to what a history needs.
pub struct Entry {
  artifact : String
  id : String
  started_at : String
  workload_version : Int32
  tier : String
  verdict : String
  harness_version : String
  manifest_sha256 : String
  commit : String
  branch : String
  dirty : Bool
  host_profile : String
  dataset_generator : String
  dataset_count : Int32
  dataset_seed : Int64
  dataset_sha256 : String
  implementations : Array[ImplementationPoint]
}

///|
/// A workload's whole history, oldest first.
pub struct Index {
  workload : String
  entries : Array[Entry]
}

///|
/// Vendor marketing marks carry no information about the machine and would
/// otherwise split equivalent model strings into different profiles.
fn strip_marks(text : String) -> String {
  let mut result = text.to_lower()
  for mark in ["(r)", "(tm)", "(c)", "(m)"] {
    result = result.replace(old=mark, new="")
  }
  result
}

///|
/// Collapse text to a lowercase `a-z0-9` slug with single hyphens. Used for the
/// host profile, so a formatting difference in a CPU model string cannot fork
/// the comparability of two runs.
pub fn slug(text : String) -> String {
  let lowered = strip_marks(text)
  let builder = StringBuilder()
  let mut written = 0
  let mut pending = false
  for character in lowered {
    let alnum = (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9')
    if alnum {
      if pending && written > 0 {
        builder.write_char('-')
      }
      pending = false
      builder.write_char(character)
      written = written + 1
    } else {
      pending = true
    }
  }
  builder.to_string()
}

///|
/// The identity of the measurement conditions. Two runs are comparable only
/// when their profiles match, so the CPU model and the governor are part of it:
/// both move the numbers more than the code does.
pub fn host_profile(environment : @artifact.EnvironmentRecord) -> String {
  let governor = environment.governor.unwrap_or("unknown")
  slug(environment.os) +
  "-" +
  slug(environment.arch) +
  "-" +
  slug(environment.cpu_model) +
  "-" +
  environment.logical_cpus.to_string() +
  "c-" +
  slug(governor)
}

///|
pub fn entry(artifact_file : String, artifact : @artifact.Artifact) -> Entry {
  let points : Array[ImplementationPoint] = []
  for implementation in artifact.implementations {
    let summary = implementation.summary
    points.push({
      id: implementation.id,
      language: implementation.language,
      reference: implementation.reference,
      median_ns: summary.map(fn(summary) { summary.median_ns }),
      cv: summary.map(fn(summary) { summary.cv }),
      samples: summary.map(fn(summary) { summary.count }).unwrap_or(0),
      correctness_ok: implementation.correctness.ok,
    })
  }
  {
    artifact: artifact_file,
    id: artifact.id,
    started_at: artifact.started_at,
    workload_version: artifact.workload_version,
    tier: artifact.tier,
    verdict: artifact.verdict_status,
    harness_version: artifact.harness_version,
    manifest_sha256: artifact.manifest_sha256,
    commit: artifact.source.commit,
    branch: artifact.source.branch,
    dirty: artifact.source.dirty,
    host_profile: host_profile(artifact.environment),
    dataset_generator: artifact.dataset.generator,
    dataset_count: artifact.dataset.count,
    dataset_seed: artifact.dataset.seed,
    dataset_sha256: artifact.dataset.sha256,
    implementations: points,
  }
}

///|
/// Order by when the run started, then by file name. The artifact id already
/// begins with a UTC stamp, so the two orders agree; the tie-break only makes
/// the choice deterministic.
pub fn build(workload : String, entries : Array[Entry]) -> Index {
  let sorted = entries.copy()
  sorted.sort_by(fn(left, right) {
    let by_time = left.started_at.compare(right.started_at)
    if by_time != 0 {
      by_time
    } else {
      left.artifact.compare(right.artifact)
    }
  })
  { workload, entries: sorted, }
}

///|
fn number(value : Double) -> Json {
  Json::number(value, repr=value.to_string())
}

///|
fn integer(value : Double, repr : String) -> Json {
  Json::number(value, repr~)
}

///|
fn optional_number(value : Double?) -> Json {
  match value {
    Some(number_value) => number(number_value)
    None => Json::null()
  }
}

///|
fn point_json(point : ImplementationPoint) -> Json {
  Json::object(
    Map([
      ("id", Json::string(point.id)),
      ("language", Json::string(point.language)),
      ("reference", Json::boolean(point.reference)),
      ("median_ns", optional_number(point.median_ns)),
      ("cv", optional_number(point.cv)),
      ("samples", integer(point.samples.to_double(), point.samples.to_string())),
      ("correctness", Json::boolean(point.correctness_ok)),
    ]),
  )
}

///|
fn entry_json(entry : Entry) -> Json {
  Json::object(
    Map([
      ("artifact", Json::string(entry.artifact)),
      ("id", Json::string(entry.id)),
      ("started_at", Json::string(entry.started_at)),
      (
        "workload_version",
        integer(
          entry.workload_version.to_double(),
          entry.workload_version.to_string(),
        ),
      ),
      ("tier", Json::string(entry.tier)),
      ("verdict", Json::string(entry.verdict)),
      ("harness_version", Json::string(entry.harness_version)),
      ("manifest_sha256", Json::string(entry.manifest_sha256)),
      (
        "source",
        Json::object(
          Map([
            ("commit", Json::string(entry.commit)),
            ("branch", Json::string(entry.branch)),
            ("dirty", Json::boolean(entry.dirty)),
          ]),
        ),
      ),
      (
        "host",
        Json::object(Map([("profile", Json::string(entry.host_profile))])),
      ),
      (
        "dataset",
        Json::object(
          Map([
            ("generator", Json::string(entry.dataset_generator)),
            (
              "count",
              integer(
                entry.dataset_count.to_double(),
                entry.dataset_count.to_string(),
              ),
            ),
            (
              "seed",
              integer(
                entry.dataset_seed.to_double(),
                entry.dataset_seed.to_string(),
              ),
            ),
            ("sha256", Json::string(entry.dataset_sha256)),
          ]),
        ),
      ),
      ("implementations", Json::array(entry.implementations.map(point_json))),
    ]),
  )
}

///|
pub fn Index::to_json(self : Index) -> Json {
  Json::object(
    Map([
      ("schema_version", integer(1.0, "1")),
      ("workload", Json::string(self.workload)),
      ("entries", Json::array(self.entries.map(entry_json))),
    ]),
  )
}

///|
fn line(builder : StringBuilder, text : String) -> Unit {
  builder.write_string(text)
  builder.write_char('\n')
}

///|
fn short_commit(commit : String) -> String {
  if commit.length() >= 12 {
    commit[:12].to_owned()
  } else {
    commit
  }
}

///|
fn implementations_of(entries : Array[Entry]) -> Array[String] {
  let ids : Array[String] = []
  for entry in entries {
    for point in entry.implementations {
      if !ids.contains(point.id) {
        ids.push(point.id)
      }
    }
  }
  ids.sort()
  ids
}

///|
fn cell(entry : Entry, implementation : String) -> String {
  for point in entry.implementations {
    if point.id == implementation {
      if !point.correctness_ok {
        return "failed"
      }
      return match point.median_ns {
        Some(median) => median.to_string()
        None => "-"
      }
    }
  }
  "-"
}

///|
fn max_cv(entry : Entry) -> String {
  let mut worst = -1.0
  for point in entry.implementations {
    match point.cv {
      Some(cv) => if cv > worst { worst = cv }
      None => ()
    }
  }
  if worst < 0.0 {
    "-"
  } else {
    (worst * 100.0).to_string() + " %"
  }
}

///|
/// Render the Markdown trend. It is grouped by host profile on purpose: mixing
/// machines in one table would invite exactly the comparison the protocol
/// forbids.
pub fn render(index : Index) -> String {
  let builder = StringBuilder()
  line(builder, "# " + index.workload + " result history")
  line(builder, "")
  line(
    builder,
    "**Generated file — do not edit by hand.** `mpf history` renders it from the " +
    "committed artifacts; the JSON artifacts remain the source of truth.",
  )
  line(builder, "")
  if index.entries.length() == 0 {
    line(builder, "No committed artifact yet.")
    return builder.to_string()
  }
  let profiles : Array[String] = []
  for entry in index.entries {
    if !profiles.contains(entry.host_profile) {
      profiles.push(entry.host_profile)
    }
  }
  profiles.sort()
  let versions : Array[String] = []
  for entry in index.entries {
    let version = "v" + entry.workload_version.to_string()
    if !versions.contains(version) {
      versions.push(version)
    }
  }
  versions.sort()
  line(
    builder,
    index.entries.length().to_string() +
    (if index.entries.length() == 1 { " artifact" } else { " artifacts" }) +
    " on " +
    profiles.length().to_string() +
    (if profiles.length() == 1 { " host profile" } else { " host profiles" }) +
    ", workload " +
    versions.join(", ") +
    ".",
  )
  line(builder, "")
  for profile in profiles {
    let entries : Array[Entry] = []
    for entry in index.entries {
      if entry.host_profile == profile {
        entries.push(entry)
      }
    }
    line(builder, "## " + profile)
    line(builder, "")
    let ids = implementations_of(entries)
    let header = StringBuilder()
    header.write_string(
      "| Artifact | Started (UTC) | Commit | Version | Verdict |",
    )
    for id in ids {
      header.write_string(" " + id + " (ns) |")
    }
    header.write_string(" max CV |")
    line(builder, header.to_string())
    let separator = StringBuilder()
    separator.write_string("| --- | --- | --- | --- | --- |")
    for _ in ids {
      separator.write_string(" ---: |")
    }
    separator.write_string(" ---: |")
    line(builder, separator.to_string())
    for entry in entries {
      let row = StringBuilder()
      row.write_string("| `" + entry.id + "` | " + entry.started_at)
      row.write_string(" | `" + short_commit(entry.commit) + "`")
      row.write_string(" | v" + entry.workload_version.to_string())
      row.write_string(" | " + entry.verdict + " |")
      for id in ids {
        row.write_string(" " + cell(entry, id) + " |")
      }
      row.write_string(" " + max_cv(entry) + " |")
      line(builder, row.to_string())
    }
    line(builder, "")
  }
  line(
    builder,
    "Each row is one measurement. Rows are comparable only within one host " +
    "profile and one workload version: a version bump changes the dataset, the " +
    "parameters or the measurement, so the version column also marks a " +
    "comparability boundary. Nothing here sums or ranks across workloads, and a " +
    "delta without its noise model is not a regression.",
  )
  builder.to_string()
}
