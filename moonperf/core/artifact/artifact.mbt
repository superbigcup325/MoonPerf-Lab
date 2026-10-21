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
  measurement_ok : Bool?
  measurement_error : String?
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
/// The harness version recorded in every artifact. Bumped when the measurement
/// or diagnostic behaviour changes; the report renders the artifact's value, so
/// an older artifact keeps its own version.
pub const HARNESS_VERSION : String = "0.1.1"

///|
pub(all) struct Artifact {
  id : String
  harness_version : String
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
  match implementation.measurement_ok {
    Some(ok) => entries.push(("measurement_ok", Json::boolean(ok)))
    None => ()
  }
  match implementation.measurement_error {
    Some(error) => entries.push(("measurement_error", Json::string(error)))
    None => ()
  }
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
                  ("version", Json::string(self.harness_version)),
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

///|
fn parse_object(value : Json, what : String) -> Map[String, Json] {
  match value {
    Json::Object(object) => object
    _ => abort("artifact: " + what + " must be an object")
  }
}

///|
fn parse_field(object : Map[String, Json], name : String) -> Json {
  match object.get(name) {
    Some(value) => value
    None => abort("artifact: missing " + name)
  }
}

///|
fn parse_string_field(object : Map[String, Json], name : String) -> String {
  match parse_field(object, name) {
    Json::String(value) => value
    _ => abort("artifact: " + name + " must be a string")
  }
}

///|
fn parse_number_field(object : Map[String, Json], name : String) -> Double {
  match parse_field(object, name) {
    Json::Number(value, ..) => value
    _ => abort("artifact: " + name + " must be a number")
  }
}

///|
fn parse_int_field(object : Map[String, Json], name : String) -> Int32 {
  parse_number_field(object, name).to_int()
}

///|
fn parse_int64_field(object : Map[String, Json], name : String) -> Int64 {
  parse_number_field(object, name).to_int64()
}

///|
fn parse_bool_field(object : Map[String, Json], name : String) -> Bool {
  match parse_field(object, name) {
    Json::True => true
    Json::False => false
    _ => abort("artifact: " + name + " must be a boolean")
  }
}

///|
fn parse_optional_string(object : Map[String, Json], name : String) -> String? {
  match object.get(name) {
    None => None
    Some(Json::Null) => None
    Some(Json::String(text)) => Some(text)
    Some(_) => abort("artifact: " + name + " must be a string or null")
  }
}

///|
fn parse_params(value : Json) -> Map[String, Json] {
  let object = parse_object(value, "params")
  let result : Map[String, Json] = Map([])
  for key in object.keys() {
    match object.get(key) {
      Some(item) => result[key] = item
      None => ()
    }
  }
  result
}

///|
fn parse_array_field(object : Map[String, Json], name : String) -> Array[Json] {
  match parse_field(object, name) {
    Json::Array(values) => values
    _ => abort("artifact: " + name + " must be an array")
  }
}

///|
fn parse_string_array(value : Json) -> Array[String] {
  let result : Array[String] = []
  match value {
    Json::Array(values) =>
      for item in values {
        match item {
          Json::String(text) => result.push(text)
          _ => abort("artifact: expected an array of strings")
        }
      }
    _ => abort("artifact: expected an array of strings")
  }
  result
}

///|
fn parse_source(value : Json) -> SourceRecord {
  let object = parse_object(value, "source")
  {
    commit: parse_string_field(object, "commit"),
    dirty: parse_bool_field(object, "dirty"),
    branch: parse_string_field(object, "branch"),
  }
}

///|
fn parse_dataset(value : Json) -> DatasetRecord {
  let object = parse_object(value, "dataset")
  {
    generator: parse_string_field(object, "generator"),
    count: parse_int_field(object, "count"),
    seed: parse_int64_field(object, "seed"),
    params: parse_params(parse_field(object, "params")),
    sha256: parse_string_field(object, "sha256"),
    bytes: parse_int_field(object, "bytes"),
  }
}

///|
fn parse_measurement(value : Json) -> MeasurementRecord {
  let object = parse_object(value, "measurement")
  {
    warmup: parse_int_field(object, "warmup"),
    repeats: parse_int_field(object, "repeats"),
    timeout_s: parse_number_field(object, "timeout_s"),
    inner_repeats: parse_int_field(object, "inner_repeats"),
    max_cv: parse_number_field(object, "max_cv"),
  }
}

///|
fn parse_environment(value : Json) -> EnvironmentRecord {
  let object = parse_object(value, "environment")
  let cpu = parse_object(parse_field(object, "cpu"), "environment.cpu")
  {
    os: parse_string_field(object, "os"),
    os_release: parse_string_field(object, "os_release"),
    arch: parse_string_field(object, "arch"),
    cpu_model: parse_string_field(cpu, "model"),
    logical_cpus: parse_int_field(cpu, "logical_cpus"),
    governor: parse_optional_string(cpu, "governor"),
    memory_bytes: parse_int64_field(object, "memory_bytes"),
  }
}

///|
fn parse_build(value : Json) -> BuildRecord {
  let object = parse_object(value, "build")
  {
    ok: parse_bool_field(object, "ok"),
    skipped: parse_bool_field(object, "skipped"),
    command: parse_optional_string(object, "command"),
    duration_ms: parse_number_field(object, "duration_ms"),
    log_sha256: parse_optional_string(object, "log_sha256"),
  }
}

///|
fn parse_correctness(value : Json) -> CorrectnessRecord {
  let object = parse_object(value, "correctness")
  let values = parse_object(parse_field(object, "values"), "correctness.values")
  let result : Map[String, Json] = Map([])
  for key in values.keys() {
    match values.get(key) {
      Some(item) => result[key] = item
      None => ()
    }
  }
  {
    ok: parse_bool_field(object, "ok"),
    mode: parse_string_field(object, "mode"),
    checked_against: parse_optional_string(object, "checked_against"),
    values: result,
    errors: parse_string_array(parse_field(object, "errors")),
  }
}

///|
fn parse_setup(value : Json) -> SetupRecord {
  let object = parse_object(value, "setup")
  {
    wall_ns: parse_int64_field(object, "wall_ns"),
    fraction: parse_number_field(object, "fraction"),
    runs: if object.get("runs") is Some(_) {
      parse_int_field(object, "runs")
    } else {
      1
    },
  }
}

///|
fn parse_summary(value : Json) -> @measure.Summary {
  let object = parse_object(value, "summary")
  @measure.make_summary(
    parse_int_field(object, "count"),
    parse_int64_field(object, "min_ns"),
    parse_number_field(object, "median_ns"),
    parse_number_field(object, "mean_ns"),
    parse_number_field(object, "stdev_ns"),
    parse_number_field(object, "cv"),
  )
}

///|
fn parse_implementation(value : Json) -> ImplementationRecord {
  let object = parse_object(value, "implementation")
  let samples : Array[Int64] = []
  for item in parse_array_field(object, "samples_ns") {
    match item {
      Json::Number(number, ..) => samples.push(number.to_int64())
      _ => abort("artifact: samples_ns must contain numbers")
    }
  }
  let setup = match object.get("setup") {
    None => None
    Some(Json::Null) => None
    Some(value) => Some(parse_setup(value))
  }
  let summary = match object.get("summary") {
    None => None
    Some(Json::Null) => None
    Some(value) => Some(parse_summary(value))
  }
  let measurement_ok = match object.get("measurement_ok") {
    None => None
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    Some(_) => abort("artifact: measurement_ok must be a boolean")
  }
  {
    id: parse_string_field(object, "id"),
    language: parse_string_field(object, "language"),
    reference: parse_bool_field(object, "reference"),
    toolchain: parse_optional_string(object, "toolchain"),
    build: parse_build(parse_field(object, "build")),
    correctness: parse_correctness(parse_field(object, "correctness")),
    samples_ns: samples,
    summary,
    measurement_ok,
    measurement_error: parse_optional_string(object, "measurement_error"),
    setup,
  }
}

///|
fn parse_comparison(value : Json) -> ComparisonRecord {
  let object = parse_object(value, "comparison")
  {
    baseline: parse_string_field(object, "baseline"),
    subject: parse_string_field(object, "subject"),
    baseline_ns: parse_number_field(object, "baseline_ns"),
    subject_ns: parse_number_field(object, "subject_ns"),
    ratio: parse_number_field(object, "ratio"),
    delta_pct: parse_number_field(object, "delta_pct"),
  }
}

///|
pub fn from_json(value : Json) -> Artifact {
  let root = parse_object(value, "root")
  if parse_int_field(root, "schema_version") != 1 {
    abort("artifact: unsupported schema_version")
  }
  let experiment = parse_object(parse_field(root, "experiment"), "experiment")
  let workload = parse_object(parse_field(experiment, "workload"), "workload")
  let implementations : Array[ImplementationRecord] = []
  for item in parse_array_field(root, "implementations") {
    implementations.push(parse_implementation(item))
  }
  let comparisons : Array[ComparisonRecord] = []
  for item in parse_array_field(root, "comparisons") {
    comparisons.push(parse_comparison(item))
  }
  let verdict = parse_object(parse_field(root, "verdict"), "verdict")
  {
    id: parse_string_field(experiment, "id"),
    harness_version: parse_string_field(
      parse_object(parse_field(experiment, "harness"), "harness"),
      "version",
    ),
    started_at: parse_string_field(experiment, "started_at"),
    finished_at: parse_string_field(experiment, "finished_at"),
    source: parse_source(parse_field(experiment, "source")),
    workload_name: parse_string_field(workload, "name"),
    workload_version: parse_int_field(workload, "version"),
    tier: parse_string_field(workload, "tier"),
    manifest_sha256: parse_string_field(workload, "manifest_sha256"),
    dataset: parse_dataset(parse_field(experiment, "dataset")),
    params: parse_params(parse_field(experiment, "params")),
    measurement: parse_measurement(parse_field(experiment, "measurement")),
    environment: parse_environment(parse_field(experiment, "environment")),
    reproduce_command: parse_string_field(experiment, "reproduce_command"),
    implementations,
    comparisons,
    verdict_status: parse_string_field(verdict, "status"),
    verdict_notes: parse_string_array(parse_field(verdict, "notes")),
  }
}
