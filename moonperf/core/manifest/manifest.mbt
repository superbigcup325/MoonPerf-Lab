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
  params : Map[String, @dataset.ParamValue]
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
/// One declared input-matrix entry: a dataset configuration the workload was
/// considered at, beside the recorded one in `[dataset]`.
pub struct MatrixVariant {
  name : String
  status : String
  description : String
  count : Int32?
  seed : Int64?
  dataset_params : Map[String, @dataset.ParamValue]
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
  matrix : Array[MatrixVariant]
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
fn param_value_of(
  key : String,
  value : @toml.TomlValue,
  context : String,
) -> @dataset.ParamValue raise ManifestError {
  match value {
    @toml.TomlInteger(number) => @dataset.ParamValue::Int(number)
    @toml.TomlFloat(number) => @dataset.ParamValue::Float(number)
    @toml.TomlString(text) => @dataset.ParamValue::Text(text)
    _ => fail(context + "." + key + " must be a scalar")
  }
}

///|
fn param_table(
  table : Map[String, @toml.TomlValue],
  key : String,
  context : String,
) -> Map[String, @dataset.ParamValue] raise ManifestError {
  let params : Map[String, @dataset.ParamValue] = Map([])
  for name, value in required_table(table, key, context) {
    params[name] = param_value_of(name, value, context + "." + key)
  }
  params
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
  let params = param_table(table, "params", "dataset")
  // The generator registry owns the per-generator parameter rules, so the
  // manifest stays agnostic about which generators exist.
  @dataset.validate(generator, params) catch {
    @dataset.DatasetError::Message(message) => fail(message)
  }
  { generator, count, seed, params, }
}

///|
/// Variants are a small declared set, never a sweep: more than this means the
/// workload should be split, not multiplied.
const MAX_MATRIX_VARIANTS : Int32 = 8

///|
fn same_params(
  left : Map[String, @dataset.ParamValue],
  right : Map[String, @dataset.ParamValue],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for key, value in left {
    let other = match right.get(key) {
      Some(other) => other
      None => return false
    }
    let equal = match (value, other) {
      (@dataset.ParamValue::Int(a), @dataset.ParamValue::Int(b)) => a == b
      (@dataset.ParamValue::Float(a), @dataset.ParamValue::Float(b)) => a == b
      (@dataset.ParamValue::Text(a), @dataset.ParamValue::Text(b)) => a == b
      _ => false
    }
    if !equal {
      return false
    }
  }
  true
}

///|
/// Apply one variant's overrides on top of the recorded dataset.
pub fn apply_variant(dataset : Dataset, variant : MatrixVariant) -> Dataset {
  let params : Map[String, @dataset.ParamValue] = Map([])
  for key, value in dataset.params {
    params[key] = value
  }
  for key, value in variant.dataset_params {
    params[key] = value
  }
  {
    generator: dataset.generator,
    count: variant.count.unwrap_or(dataset.count),
    seed: variant.seed.unwrap_or(dataset.seed),
    params,
  }
}

///|
/// The dataset one declared variant describes, or a failure naming the
/// variants the manifest does declare.
pub fn variant_dataset(
  workload : Workload,
  name : String,
) -> Dataset raise ManifestError {
  let known : Array[String] = []
  for variant in workload.matrix {
    known.push(variant.name)
    if variant.name == name {
      return apply_variant(workload.dataset, variant)
    }
  }
  if known.length() == 0 {
    fail(workload.name + ": declares no input matrix")
  }
  fail(
    workload.name +
    ": unknown variant '" +
    name +
    "'; declared: " +
    known.join(", "),
  )
}

///|
/// The tool accepts `[matrix.<name>]` tables; a variant may override `count`,
/// `seed` and `dataset.params` (merged key by key over `[dataset.params]`).
/// Every variant must stay a legal dataset of the same generator and must
/// differ from the recorded configuration, so the matrix never restates it.
fn parse_matrix(
  table : Map[String, @toml.TomlValue],
  dataset : Dataset,
) -> Array[MatrixVariant] raise ManifestError {
  let variants : Array[MatrixVariant] = []
  let names = table.keys().to_array()
  names.sort()
  if names.length() > MAX_MATRIX_VARIANTS {
    fail(
      "manifest.matrix may declare at most " +
      MAX_MATRIX_VARIANTS.to_string() +
      " variants; split the workload instead of multiplying it",
    )
  }
  for name in names {
    let context = "matrix." + name
    if !is_identifier(name) {
      fail(
        context + ": variant names must match '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'",
      )
    }
    let entry = table_of(table[name], context)
    let status = required_string(entry, "status", context)
    one_of(status, ["probe", "rejected"], context + ".status")
    let description = required_string(entry, "description", context)
    if description.length() == 0 || description.length() > 240 {
      fail(context + ".description must be 1 to 240 characters")
    }
    let count = match entry.get("count") {
      None => None
      Some(@toml.TomlInteger(number)) => Some(number.to_int())
      Some(_) => fail(context + ".count must be an integer")
    }
    match count {
      Some(value) => if value <= 0 { fail(context + ".count must be positive") }
      None => ()
    }
    let seed = match entry.get("seed") {
      None => None
      Some(@toml.TomlInteger(number)) => Some(number)
      Some(_) => fail(context + ".seed must be an integer")
    }
    match seed {
      Some(value) =>
        if value < 0L {
          fail(context + ".seed must be non-negative")
        }
      None => ()
    }
    let overrides = match entry.get("dataset_params") {
      None => (Map([]) : Map[String, @dataset.ParamValue])
      Some(_) => param_table(entry, "dataset_params", context)
    }
    if count == None && seed == None && overrides.length() == 0 {
      fail(
        context + " must override at least one of count, seed or dataset_params",
      )
    }
    let variant = {
      name,
      status,
      description,
      count,
      seed,
      dataset_params: overrides,
    }
    let effective = apply_variant(dataset, variant)
    @dataset.validate(dataset.generator, effective.params) catch {
      @dataset.DatasetError::Message(message) => fail(context + ": " + message)
    }
    if effective.count == dataset.count &&
      effective.seed == dataset.seed &&
      same_params(effective.params, dataset.params) {
      fail(context + " must differ from the recorded [dataset] configuration")
    }
    variants.push(variant)
  }
  variants
}

///|
/// Variant names are part of the manifest contract, so the pattern is checked
/// here rather than delegated to a regular-expression dependency.
fn is_identifier(text : String) -> Bool {
  let mut length = 0
  let mut previous_hyphen = true
  for character in text {
    let lower = character >= 'a' && character <= 'z'
    let digit = character >= '0' && character <= '9'
    if length == 0 && !lower {
      return false
    }
    if !(lower || digit || character == '-') {
      return false
    }
    if character == '-' && previous_hyphen {
      return false
    }
    previous_hyphen = character == '-'
    length = length + 1
  }
  length > 0 && length <= 64 && !previous_hyphen
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
  let matrix = match table.get("matrix") {
    Some(value) => parse_matrix(table_of(value, "manifest.matrix"), dataset)
    None => []
  }
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
    matrix,
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
