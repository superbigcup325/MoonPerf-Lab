///|
pub suberror ManifestError {
  Message(String)
}

///|
fn[T] fail(message : String) -> T raise ManifestError {
  raise ManifestError::Message(message)
}

///|
pub fn basename(path : String) -> String {
  match path.rev_after("/") {
    Some(name) => name.to_owned()
    None => path
  }
}

///|
pub fn parent(path : String) -> String {
  match path.rev_before("/") {
    Some(directory) =>
      if directory.length() == 0 {
        "/"
      } else {
        directory.to_owned()
      }
    None => "."
  }
}

///|
pub fn join(directory : String, name : String) -> String {
  if directory.has_suffix("/") {
    directory + name
  } else {
    directory + "/" + name
  }
}

///|
pub struct Dataset {
  generator : String
  count : Int32
  seed : Int64
  min_value : Double
  max_value : Double
}

///|
pub struct Verify {
  mode : String
  reference : String?
  rtol : Double?
  atol : Double?
  fields : Array[String]
}

///|
pub struct Measurement {
  warmup : Int32
  repeats : Int32
  timeout_s : Double
  inner_repeats : Int32
  max_cv : Double
}

///|
pub struct Implementation {
  id : String
  directory : String
  language : String
  summary : String?
  build_dir : String?
}

///|
pub struct Workload {
  manifest_path : String
  directory : String
  name : String
  version : Int32
  status : String
  tier : String
  summary : String?
  dataset : Dataset
  params : Map[String, @toml.TomlValue]
  verify : Verify
  measurement : Measurement
  mut implementations : Array[Implementation]
}

///|
fn table_of(
  value : @toml.TomlValue,
  context : String,
) -> Map[String, @toml.TomlValue] raise ManifestError {
  match value {
    @toml.TomlTable(table) => table
    _ => fail(context + " must be a table")
  }
}

///|
fn required(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> @toml.TomlValue raise ManifestError {
  match table.get(key) {
    Some(value) => value
    None => fail(context + ": missing " + key)
  }
}

///|
fn required_table(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Map[String, @toml.TomlValue] raise ManifestError {
  table_of(required(table, key, context), context + "." + key)
}

///|
fn required_string(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> String raise ManifestError {
  match required(table, key, context) {
    @toml.TomlString(value) => value
    _ => fail(context + "." + key + " must be a string")
  }
}

///|
fn optional_string(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> String? raise ManifestError {
  match table.get(key) {
    None => None
    Some(@toml.TomlString(value)) => Some(value)
    Some(_) => fail(context + "." + key + " must be a string")
  }
}

///|
fn required_int(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Int32 raise ManifestError {
  match required(table, key, context) {
    @toml.TomlInteger(value) => value.to_int()
    _ => fail(context + "." + key + " must be an integer")
  }
}

///|
fn required_int64(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Int64 raise ManifestError {
  match required(table, key, context) {
    @toml.TomlInteger(value) => value
    _ => fail(context + "." + key + " must be an integer")
  }
}

///|
fn number_of(
  value : @toml.TomlValue,
  context : String,
) -> Double raise ManifestError {
  match value {
    @toml.TomlFloat(number) => number
    @toml.TomlInteger(number) => number.to_double()
    _ => fail(context + " must be a number")
  }
}

///|
fn required_number(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Double raise ManifestError {
  number_of(required(table, key, context), context + "." + key)
}

///|
fn optional_number(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Double? raise ManifestError {
  match table.get(key) {
    None => None
    Some(value) => Some(number_of(value, context + "." + key))
  }
}

///|
fn required_string_array(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Array[String] raise ManifestError {
  match required(table, key, context) {
    @toml.TomlArray(values) => {
      let result : Array[String] = []
      for value in values {
        match value {
          @toml.TomlString(item) => result.push(item)
          _ => fail(context + "." + key + " must contain strings")
        }
      }
      if result.length() == 0 {
        fail(context + "." + key + " must not be empty")
      }
      result
    }
    _ => fail(context + "." + key + " must be an array")
  }
}

///|
fn one_of(
  value : String,
  allowed : Array[String],
  context : String,
) -> Unit raise ManifestError {
  for candidate in allowed {
    if value == candidate {
      return
    }
  }
  fail(context + " must be one of " + allowed.join(", ") + ", got " + value)
}

///|
fn parse_dataset(
  table : Map[String, @toml.TomlValue],
) -> Dataset raise ManifestError {
  let generator = required_string(table, "generator", "dataset")
  let count = required_int(table, "count", "dataset")
  let seed = required_int64(table, "seed", "dataset")
  if count <= 0 {
    fail("dataset.count must be positive")
  }
  if seed < 0L {
    fail("dataset.seed must be non-negative")
  }
  let params = required_table(table, "params", "dataset")
  let min_value = required_number(params, "min", "dataset.params")
  let max_value = required_number(params, "max", "dataset.params")
  if !(min_value < max_value) {
    fail("dataset.params.min must be below dataset.params.max")
  }
  if generator != "uniform-f64" {
    fail("dataset.generator is not implemented by the core: " + generator)
  }
  { generator, count, seed, min_value, max_value, }
}

///|
fn parse_verify(
  table : Map[String, @toml.TomlValue],
) -> Verify raise ManifestError {
  let mode = required_string(table, "mode", "verify")
  one_of(mode, ["exact", "tolerance"], "verify.mode")
  let fields = required_string_array(table, "fields", "verify")
  let reference = optional_string(table, "reference", "verify")
  let rtol = optional_number(table, "rtol", "verify")
  let atol = optional_number(table, "atol", "verify")
  if mode == "tolerance" && rtol == None {
    fail("verify.rtol is required in tolerance mode")
  }
  { mode, reference, rtol, atol, fields, }
}

///|
fn parse_measurement(
  table : Map[String, @toml.TomlValue],
) -> Measurement raise ManifestError {
  let warmup = required_int(table, "warmup", "measurement")
  let repeats = required_int(table, "repeats", "measurement")
  let timeout_s = required_number(table, "timeout_s", "measurement")
  let inner_repeats = required_int(table, "inner_repeats", "measurement")
  let max_cv = optional_number(table, "max_cv", "measurement").unwrap_or(0.05)
  if warmup < 0 {
    fail("measurement.warmup must be non-negative")
  }
  if repeats < 1 {
    fail("measurement.repeats must be at least 1")
  }
  if timeout_s <= 0.0 {
    fail("measurement.timeout_s must be positive")
  }
  if inner_repeats < 1 {
    fail("measurement.inner_repeats must be at least 1")
  }
  if max_cv <= 0.0 || max_cv > 1.0 {
    fail("measurement.max_cv must be in (0, 1]")
  }
  { warmup, repeats, timeout_s, inner_repeats, max_cv, }
}

///|
/// Parse a workload manifest without touching the filesystem. `directory` is
/// the workload directory; its basename must equal `name`.
pub fn parse_manifest_text(
  directory : String,
  text : String,
) -> Workload raise ManifestError {
  let root = @toml.parse(text) catch {
    error => fail("invalid TOML: " + error.to_string())
  }
  let table = table_of(root, "manifest")
  let schema_version = required_int(table, "schema_version", "manifest")
  if schema_version != 1 {
    fail("manifest.schema_version must be 1")
  }
  let name = required_string(table, "name", "manifest")
  let expected_name = basename(directory)
  if name != expected_name {
    fail(
      "manifest.name '" +
      name +
      "' must match the directory '" +
      expected_name +
      "'",
    )
  }
  let version = required_int(table, "version", "manifest")
  if version < 1 {
    fail("manifest.version must be positive")
  }
  let status = required_string(table, "status", "manifest")
  one_of(status, ["draft", "active", "retired"], "manifest.status")
  let tier = required_string(table, "tier", "manifest")
  one_of(tier, ["micro", "component", "end-to-end"], "manifest.tier")
  let summary = optional_string(table, "summary", "manifest")
  let dataset = parse_dataset(required_table(table, "dataset", "manifest"))
  let params = match table.get("params") {
    Some(value) => table_of(value, "manifest.params")
    None => Map([])
  }
  let verify = parse_verify(required_table(table, "verify", "manifest"))
  let measurement = parse_measurement(
    required_table(table, "measurement", "manifest"),
  )
  {
    manifest_path: join(directory, "workload.toml"),
    directory,
    name,
    version,
    status,
    tier,
    summary,
    dataset,
    params,
    verify,
    measurement,
    implementations: [],
  }
}

///|
async fn parse_adapter(
  directory : String,
  id : String,
) -> Implementation raise ManifestError {
  let adapter_path = join(directory, "adapter.toml")
  let data = @fs.read_file(adapter_path) catch {
    _ => fail(adapter_path + ": cannot read adapter")
  }
  let text = data.text() catch {
    _ => fail(adapter_path + ": adapter is not UTF-8 text")
  }
  let root = @toml.parse(text) catch {
    error => fail(adapter_path + ": invalid TOML: " + error.to_string())
  }
  let table = table_of(root, adapter_path)
  let schema_version = required_int(table, "schema_version", "adapter")
  if schema_version != 1 {
    fail(adapter_path + ": adapter.schema_version must be 1")
  }
  let language = required_string(table, "language", "adapter")
  let summary = optional_string(table, "summary", "adapter")
  let build_dir = optional_string(table, "build_dir", "adapter")
  let run_script = join(directory, "run.sh")
  if !(@fs.exists(run_script) catch { _ => false }) {
    fail(directory + ": missing run.sh")
  }
  if !(@fs.can_execute(run_script) catch { _ => false }) {
    fail(run_script + ": not executable (chmod +x it)")
  }
  { id, directory, language, summary, build_dir, }
}

///|
pub async fn discover_implementations(
  workload_directory : String,
) -> Array[Implementation] raise ManifestError {
  let base = join(workload_directory, "implementations")
  if !(@fs.exists(base) catch { _ => false }) {
    return []
  }
  let entries = @fs.readdir(base, sort=true) catch {
    _ => fail(base + ": cannot read directory")
  }
  entries.sort()
  let implementations : Array[Implementation] = []
  for id in entries {
    let directory = join(base, id)
    let adapter_path = join(directory, "adapter.toml")
    if !(@fs.exists(adapter_path) catch { _ => false }) {
      continue
    }
    implementations.push(parse_adapter(directory, id))
  }
  implementations
}

///|
pub async fn load_workload(
  manifest_path : String,
) -> Workload raise ManifestError {
  let directory = parent(manifest_path)
  let data = @fs.read_file(manifest_path) catch {
    _ => fail(manifest_path + ": cannot read manifest")
  }
  let text = data.text() catch {
    _ => fail(manifest_path + ": manifest is not UTF-8 text")
  }
  let workload = parse_manifest_text(directory, text)
  let implementations = discover_implementations(directory)
  workload.implementations = implementations
  if workload.status == "active" && implementations.length() == 0 {
    fail(
      workload.name +
      ": status is active but no implementations were discovered",
    )
  }
  match workload.verify.reference {
    None => ()
    Some(reference) => {
      let mut found = false
      for implementation in implementations {
        if implementation.id == reference {
          found = true
        }
      }
      if !found {
        fail(
          workload.name +
          ": verify.reference '" +
          reference +
          "' is not a discovered implementation",
        )
      }
    }
  }
  workload
}

///|
pub async fn discover_workload_paths(root : String) -> Array[String] {
  let entries = @fs.readdir(root, sort=true) catch { _ => [] }
  let paths : Array[String] = []
  for name in entries {
    let manifest = join(join(root, name), "workload.toml")
    if (@fs.exists(manifest) catch { _ => false }) {
      paths.push(manifest)
    }
  }
  paths
}
