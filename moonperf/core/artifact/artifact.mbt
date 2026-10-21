///|
pub(all) struct DatasetRecord {
  generator : String
  count : Int32
  seed : Int64
  params : Map[String, Json]
  sha256 : String
  bytes : Int32
}

///|
pub(all) struct SourceRecord {
  commit : String
  dirty : Bool
  branch : String
}

///|
pub(all) struct EnvironmentRecord {
  os : String
  os_release : String
  arch : String
  cpu_model : String
  logical_cpus : Int32
  governor : String?
  memory_bytes : Int64
}

///|
pub(all) struct MeasurementRecord {
  warmup : Int32
  repeats : Int32
  timeout_s : Double
  inner_repeats : Int32
  max_cv : Double
}

///|
pub(all) struct SetupRecord {
  wall_ns : Int64
  fraction : Double
  runs : Int32
}

///|
pub(all) struct BuildRecord {
  ok : Bool
  skipped : Bool
  command : String?
  duration_ms : Double
  log_sha256 : String?
}

///|
pub(all) struct CorrectnessRecord {
  ok : Bool
  mode : String
  checked_against : String?
  values : Map[String, Json]
  errors : Array[String]
}

///|
pub(all) struct ImplementationRecord {
  id : String
  language : String
  reference : Bool
  toolchain : String?
  build : BuildRecord
  correctness : CorrectnessRecord
  samples_ns : Array[Int64]
  summary : @measure.Summary?
  setup : SetupRecord?
}

///|
pub(all) struct ComparisonRecord {
  baseline : String
  subject : String
  baseline_ns : Double
  subject_ns : Double
  ratio : Double
  delta_pct : Double
}

///|
pub(all) struct Artifact {
  id : String
  started_at : String
  finished_at : String
  source : SourceRecord
  workload_name : String
  workload_version : Int32
  tier : String
  manifest_sha256 : String
  dataset : DatasetRecord
  params : Map[String, Json]
  measurement : MeasurementRecord
  environment : EnvironmentRecord
  reproduce_command : String
  implementations : Array[ImplementationRecord]
  comparisons : Array[ComparisonRecord]
  verdict_status : String
  verdict_notes : Array[String]
}

///|
fn json_int(value : Int32) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_int64(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_optional_string(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn summary_json(summary : @measure.Summary) -> Json {
  Json::object(
    Map([
      ("count", json_int(summary.count)),
      ("min_ns", json_int64(summary.min_ns)),
      ("median_ns", Json::number(summary.median_ns)),
      ("mean_ns", Json::number(summary.mean_ns)),
      ("stdev_ns", Json::number(summary.stdev_ns)),
      ("cv", Json::number(summary.cv)),
    ]),
  )
}

///|
fn build_json(build : BuildRecord) -> Json {
  let entries : Array[(String, Json)] = [
    ("ok", Json::boolean(build.ok)),
    ("skipped", Json::boolean(build.skipped)),
  ]
  match build.command {
    Some(command) => entries.push(("command", Json::string(command)))
    None => ()
  }
  entries.push(("duration_ms", Json::number(build.duration_ms)))
  match build.log_sha256 {
    Some(hash) => entries.push(("log_sha256", Json::string(hash)))
    None => ()
  }
  Json::object(Map(entries))
}

///|
fn correctness_json(correctness : CorrectnessRecord) -> Json {
  Json::object(
    Map([
      ("ok", Json::boolean(correctness.ok)),
      ("mode", Json::string(correctness.mode)),
      ("checked_against", json_optional_string(correctness.checked_against)),
      ("values", Json::object(correctness.values)),
      ("errors", Json::array(correctness.errors.map(Json::string))),
    ]),
  )
}

///|
fn implementation_json(implementation : ImplementationRecord) -> Json {
  let entries : Array[(String, Json)] = [
    ("id", Json::string(implementation.id)),
    ("language", Json::string(implementation.language)),
    ("reference", Json::boolean(implementation.reference)),
    ("toolchain", json_optional_string(implementation.toolchain)),
    ("build", build_json(implementation.build)),
    ("correctness", correctness_json(implementation.correctness)),
    ("samples_ns", Json::array(implementation.samples_ns.map(json_int64))),
    (
      "summary",
      match implementation.summary {
        Some(summary) => summary_json(summary)
        None => Json::null()
      },
    ),
  ]
  match implementation.setup {
    Some(setup) =>
      entries.push(
        (
          "setup",
          Json::object(
            Map([
              ("inner_repeats", json_int(0)),
              ("wall_ns", json_int64(setup.wall_ns)),
              ("fraction", Json::number(setup.fraction)),
              ("runs", json_int(setup.runs)),
            ]),
          ),
        ),
      )
    None => ()
  }
  Json::object(Map(entries))
}

///|
fn comparison_json(comparison : ComparisonRecord) -> Json {
  Json::object(
    Map([
      ("baseline", Json::string(comparison.baseline)),
      ("subject", Json::string(comparison.subject)),
      ("metric", Json::string("median_ns")),
      ("baseline_ns", Json::number(comparison.baseline_ns)),
      ("subject_ns", Json::number(comparison.subject_ns)),
      ("ratio", Json::number(comparison.ratio)),
      ("delta_pct", Json::number(comparison.delta_pct)),
    ]),
  )
}

///|
pub fn Artifact::to_json(self : Artifact) -> Json {
  Json::object(
    Map([
      ("schema_version", json_int(1)),
      (
        "experiment",
        Json::object(
          Map([
            ("id", Json::string(self.id)),
            ("started_at", Json::string(self.started_at)),
            ("finished_at", Json::string(self.finished_at)),
            (
              "harness",
              Json::object(
                Map([
                  ("name", Json::string("moonperf")),
                  ("version", Json::string("0.1.0")),
                  ("runtime", Json::string("MoonBit native")),
                ]),
              ),
            ),
            (
              "source",
              Json::object(
                Map([
                  ("commit", Json::string(self.source.commit)),
                  ("dirty", Json::boolean(self.source.dirty)),
                  ("branch", Json::string(self.source.branch)),
                ]),
              ),
            ),
            (
              "workload",
              Json::object(
                Map([
                  ("name", Json::string(self.workload_name)),
                  ("version", json_int(self.workload_version)),
                  ("tier", Json::string(self.tier)),
                  ("manifest_sha256", Json::string(self.manifest_sha256)),
                ]),
              ),
            ),
            (
              "dataset",
              Json::object(
                Map([
                  ("generator", Json::string(self.dataset.generator)),
                  ("count", json_int(self.dataset.count)),
                  ("seed", json_int64(self.dataset.seed)),
                  ("params", Json::object(self.dataset.params)),
                  ("sha256", Json::string(self.dataset.sha256)),
                  ("bytes", json_int(self.dataset.bytes)),
                ]),
              ),
            ),
            ("params", Json::object(self.params)),
            (
              "measurement",
              Json::object(
                Map([
                  ("warmup", json_int(self.measurement.warmup)),
                  ("repeats", json_int(self.measurement.repeats)),
                  ("timeout_s", Json::number(self.measurement.timeout_s)),
                  ("inner_repeats", json_int(self.measurement.inner_repeats)),
                  ("max_cv", Json::number(self.measurement.max_cv)),
                  ("order", Json::string("round-robin")),
                  ("clock", Json::string("monotonic")),
                ]),
              ),
            ),
            (
              "environment",
              Json::object(
                Map([
                  ("os", Json::string(self.environment.os)),
                  ("os_release", Json::string(self.environment.os_release)),
                  ("arch", Json::string(self.environment.arch)),
                  (
                    "cpu",
                    Json::object(
                      Map([
                        ("model", Json::string(self.environment.cpu_model)),
                        (
                          "logical_cpus",
                          json_int(self.environment.logical_cpus),
                        ),
                        (
                          "governor",
                          json_optional_string(self.environment.governor),
                        ),
                      ]),
                    ),
                  ),
                  ("memory_bytes", json_int64(self.environment.memory_bytes)),
                ]),
              ),
            ),
            ("reproduce_command", Json::string(self.reproduce_command)),
          ]),
        ),
      ),
      (
        "implementations",
        Json::array(self.implementations.map(implementation_json)),
      ),
      ("comparisons", Json::array(self.comparisons.map(comparison_json))),
      (
        "verdict",
        Json::object(
          Map([
            ("status", Json::string(self.verdict_status)),
            ("notes", Json::array(self.verdict_notes.map(Json::string))),
          ]),
        ),
      ),
    ]),
  )
}
