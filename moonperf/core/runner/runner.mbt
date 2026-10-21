///|
priv struct RunState {
  implementation : @manifest.Implementation
  toolchain : String?
  build : @artifact.BuildRecord
  mut correctness : @artifact.CorrectnessRecord
  samples_ns : Array[Int64]
  mut summary : @measure.Summary?
  mut measurement_error : String?
  mut setup : @artifact.SetupRecord?
}

///|
fn join(directory : String, name : String) -> String {
  if directory.has_suffix("/") {
    directory + name
  } else {
    directory + "/" + name
  }
}

///|
fn trim(text : String) -> String {
  text.trim().to_owned()
}

///|
async fn read_text(path : String) -> String {
  let data = @fs.read_file(path) catch { _ => return "" }
  data.text() catch {
    _ => ""
  }
}

///|
async fn capture_stdout(
  command : String,
  args : Array[String],
  cwd : String,
) -> String {
  let directory = @fs.tmpdir(prefix="mpf-meta-") catch { _ => return "" }
  let stdout_path = join(directory, "stdout.txt")
  let stderr_path = join(directory, "stderr.txt")
  let _ = ignore(
    @host.run(command, args, Some(cwd), 10000, stdout_path, stderr_path),
  ) catch {
    _ => ()
  }
  let text = read_text(stdout_path)
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
  trim(text)
}

///|
async fn source_record(repo_root : String) -> @artifact.SourceRecord {
  let commit = capture_stdout("git", ["rev-parse", "HEAD"], repo_root)
  let branch = capture_stdout(
    "git",
    ["rev-parse", "--abbrev-ref", "HEAD"],
    repo_root,
  )
  let status = capture_stdout("git", ["status", "--porcelain"], repo_root)
  if commit.length() != 40 {
    abort("the experiment requires a git checkout with a HEAD commit")
  }
  { commit, dirty: status.length() > 0, branch, }
}

///|
async fn environment_record() -> @artifact.EnvironmentRecord {
  let cpuinfo = read_text("/proc/cpuinfo")
  let mut cpu_model = "unknown"
  let mut logical_cpus = 0
  for line in cpuinfo.split("\n") {
    if line.has_prefix("model name") && cpu_model == "unknown" {
      let parts = line.split(":")
      let values = parts.to_array()
      if values.length() > 1 {
        cpu_model = trim(values[1].to_owned())
      }
    }
    if line.has_prefix("processor") {
      logical_cpus = logical_cpus + 1
    }
  }
  let meminfo = read_text("/proc/meminfo")
  let mut memory_bytes : Int64 = 1L
  for line in meminfo.split("\n") {
    if line.has_prefix("MemTotal:") {
      let parts = line.split(" ")
      let values = parts.to_array()
      let mut index = 0
      while index < values.length() {
        let value = values[index].to_owned()
        if value.length() > 0 && value != "MemTotal:" && value != "kB" {
          let number = @string.parse_int64(value) catch { _ => 0L }
          if number > 0L {
            memory_bytes = number * 1024L
            break
          }
        }
        index = index + 1
      }
    }
  }
  let os_release = parse_os_release(read_text("/etc/os-release"))
  let arch = capture_stdout("uname", ["-m"], ".")
  let governor = parse_governor(
    read_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
  )
  {
    os: "Linux",
    os_release,
    arch: if arch.length() == 0 {
      "unknown"
    } else {
      arch
    },
    cpu_model,
    logical_cpus: if logical_cpus == 0 {
      1
    } else {
      logical_cpus
    },
    governor,
    memory_bytes,
  }
}

///|
fn parse_os_release(text : String) -> String {
  for line in text.split("\n") {
    if line.has_prefix("PRETTY_NAME=") {
      let value = line.exact_view(start=12).to_owned()
      if value.has_prefix("\"") && value.has_suffix("\"") && value.length() >= 2 {
        return value.exact_view(start=1, end=value.length() - 1).to_owned()
      }
      return value
    }
  }
  "unknown"
}

///|
fn parse_governor(text : String) -> String? {
  let value = trim(text)
  if value.length() == 0 {
    None
  } else {
    Some(value)
  }
}

///|
fn toml_to_json(value : @toml.TomlValue) -> Json? {
  match value {
    @toml.TomlString(value) => Some(Json::string(value))
    @toml.TomlInteger(value) =>
      Some(Json::number(value.to_double(), repr=value.to_string()))
    @toml.TomlFloat(value) => Some(Json::number(value))
    @toml.TomlBoolean(value) => Some(Json::boolean(value))
    _ => None
  }
}

///|
/// The dataset parameters as recorded in the artifact. The manifest carries
/// them generically, so the artifact does too; a float stays a JSON float and
/// an integer stays a JSON integer.
fn dataset_params_json(
  params : Map[String, @dataset.ParamValue],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for key, value in params {
    result[key] = match value {
      @dataset.ParamValue::Int(number) =>
        Json::number(number.to_double(), repr=number.to_string())
      @dataset.ParamValue::Float(number) => Json::number(number)
      @dataset.ParamValue::Text(text) => Json::string(text)
    }
  }
  result
}

///|
fn params_json(params : Map[String, @toml.TomlValue]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for key, value in params {
    match toml_to_json(value) {
      Some(json) => result[key] = json
      None => ()
    }
  }
  result
}

///|
fn params_text(params : Map[String, @toml.TomlValue]) -> String {
  let keys = params.keys().to_array()
  keys.sort()
  let builder = StringBuilder()
  for key in keys {
    match params.get(key) {
      Some(@toml.TomlString(value)) =>
        builder.write_string(key + "=" + value + "\n")
      Some(@toml.TomlInteger(value)) =>
        builder.write_string(key + "=" + value.to_string() + "\n")
      Some(@toml.TomlFloat(value)) =>
        builder.write_string(key + "=" + value.to_string() + "\n")
      Some(@toml.TomlBoolean(value)) =>
        builder.write_string(
          key + "=" + (if value { "true" } else { "false" }) + "\n",
        )
      _ => ()
    }
  }
  builder.to_string()
}

///|
async fn clean_build_dir(implementation : @manifest.Implementation) -> Unit {
  match implementation.build_dir {
    Some(build_dir) =>
      @fs.rmdir(join(implementation.directory, build_dir), recursive=true) catch {
        _ => ()
      }
    None => ()
  }
}

///|
async fn toolchain_for(implementation : @manifest.Implementation) -> String? {
  let script = join(implementation.directory, "describe.sh")
  if !(@fs.exists(script) catch { _ => false }) {
    return None
  }
  let text = capture_stdout("./describe.sh", [], implementation.directory)
  if text.length() == 0 {
    return None
  }
  let parsed = @json.parse(text) catch { _ => return None }
  match parsed {
    Json::Object(object) =>
      match object.get("toolchain") {
        Some(Json::String(toolchain)) => Some(toolchain)
        _ => None
      }
    _ => None
  }
}

///|
async fn build_implementation(
  implementation : @manifest.Implementation,
  out_dir : String,
) -> @artifact.BuildRecord {
  let build_script = join(implementation.directory, "build.sh")
  if !(@fs.exists(build_script) catch { _ => false }) {
    return {
      ok: true,
      skipped: true,
      command: None,
      duration_ms: 0.0,
      log_sha256: None,
    }
  }
  clean_build_dir(implementation)
  let stdout_path = join(out_dir, implementation.id + "-build.stdout.txt")
  let stderr_path = join(out_dir, implementation.id + "-build.stderr.txt")
  let result = @host.run(
    "./build.sh",
    [],
    Some(implementation.directory),
    900000,
    stdout_path,
    stderr_path,
  ) catch {
    error =>
      raise @host.error("build failed to start: " + @host.message_of(error))
  }
  let log = read_text(stdout_path) + read_text(stderr_path)
  {
    ok: !result.timed_out && result.exit_code == 0,
    skipped: false,
    command: Some("./build.sh"),
    duration_ms: result.wall_us / 1000.0,
    log_sha256: if log.length() > 0 {
      Some(@dataset.sha256_hex(@utf8.encode(log)))
    } else {
      None
    },
  }
}

///|
async fn adapter_run(
  implementation : @manifest.Implementation,
  dataset_path : String,
  params_path : String,
  output_path : String,
  repeat : Int32,
  timeout_s : Double,
) -> @host.CommandResult {
  @host.run(
    "./run.sh",
    [
      "--input",
      dataset_path,
      "--params",
      params_path,
      "--output",
      output_path,
      "--repeat",
      repeat.to_string(),
    ],
    Some(implementation.directory),
    (timeout_s * 1000.0).to_int(),
    output_path + ".stdout.txt",
    output_path + ".stderr.txt",
  )
}

///|
async fn verify_implementation(
  state : RunState,
  dataset_path : String,
  params_path : String,
  output_dir : String,
  reference_values : Map[String, Json]?,
  workload : @manifest.Workload,
  timeout_s : Double,
) -> Unit {
  let output_path = join(
    output_dir,
    state.implementation.id + "-correctness.json",
  )
  let result = adapter_run(
    state.implementation,
    dataset_path,
    params_path,
    output_path,
    workload.measurement.inner_repeats,
    timeout_s,
  ) catch {
    error => raise @host.error("correctness run failed: " + error.to_string())
  }
  if result.timed_out {
    state.correctness = {
      ok: false,
      mode: workload.verify.mode,
      checked_against: None,
      values: Map([]),
      errors: ["correctness run timed out"],
    }
    return
  }
  if result.exit_code != 0 {
    state.correctness = {
      ok: false,
      mode: workload.verify.mode,
      checked_against: None,
      values: Map([]),
      errors: ["correctness run exited " + result.exit_code.to_string()],
    }
    return
  }
  let (values, errors) = @verify.read_output(
    output_path,
    workload.verify.fields,
  ) catch {
    _ => (Map([]), ["cannot read correctness output"])
  }
  let checked_against = if state.implementation.id ==
    workload.verify.reference.unwrap_or("") {
    None
  } else {
    workload.verify.reference
  }
  if checked_against is None {
    state.correctness = {
      ok: errors.length() == 0,
      mode: workload.verify.mode,
      checked_against: None,
      values,
      errors,
    }
    return
  }
  match reference_values {
    None =>
      state.correctness = {
        ok: false,
        mode: workload.verify.mode,
        checked_against,
        values,
        errors: [
          "reference implementation '" +
          workload.verify.reference.unwrap_or("") +
          "' did not pass",
        ],
      }
    Some(reference_values) => {
      let comparison_errors = errors +
        @verify.compare_values(
          values,
          reference_values,
          workload.verify.fields,
          workload.verify.mode,
          workload.verify.rtol.unwrap_or(0.0),
          workload.verify.atol.unwrap_or(0.0),
        )
      state.correctness = {
        ok: comparison_errors.length() == 0,
        mode: workload.verify.mode,
        checked_against,
        values,
        errors: comparison_errors,
      }
    }
  }
}

///|
async fn run_measurement(
  state : RunState,
  dataset_path : String,
  params_path : String,
  output_dir : String,
  workload : @manifest.Workload,
  round : Int32,
) -> String? {
  let output_path = join(
    output_dir,
    state.implementation.id + "-sample-" + round.to_string() + ".json",
  )
  let result = adapter_run(
    state.implementation,
    dataset_path,
    params_path,
    output_path,
    workload.measurement.inner_repeats,
    workload.measurement.timeout_s,
  ) catch {
    error => return Some("measurement run failed: " + error.to_string())
  }
  if result.timed_out {
    return Some("measurement timed out")
  }
  if result.exit_code != 0 {
    return Some("measurement exited " + result.exit_code.to_string())
  }
  let sample_ns = (result.wall_us *
  1000.0 /
  workload.measurement.inner_repeats.to_double()).to_int64()
  state.samples_ns.push(sample_ns)
  None
}

///|
async fn run_setup_baseline(
  state : RunState,
  dataset_path : String,
  params_path : String,
  output_dir : String,
  workload : @manifest.Workload,
) -> Unit {
  let walls : Array[Int64] = []
  for run in 0..<3 {
    let output_path = join(
      output_dir,
      state.implementation.id + "-setup-" + run.to_string() + ".json",
    )
    let result = adapter_run(
      state.implementation,
      dataset_path,
      params_path,
      output_path,
      0,
      workload.measurement.timeout_s,
    ) catch {
      error => raise @host.error("setup baseline failed: " + error.to_string())
    }
    if result.timed_out || result.exit_code != 0 {
      raise @host.error("setup baseline failed for " + state.implementation.id)
    }
    walls.push((result.wall_us * 1000.0).to_int64())
  }
  walls.sort()
  state.setup = Some({
    wall_ns: walls[walls.length() / 2],
    fraction: 0.0,
    runs: walls.length(),
  })
}

///|
async fn scaling_wall_ns(
  state : RunState,
  dataset_path : String,
  params_path : String,
  output_dir : String,
  workload : @manifest.Workload,
  repeat : Int32,
) -> Int64? {
  let output_path = join(
    output_dir,
    state.implementation.id + "-scaling-" + repeat.to_string() + ".json",
  )
  let result = adapter_run(
    state.implementation,
    dataset_path,
    params_path,
    output_path,
    repeat,
    workload.measurement.timeout_s,
  ) catch {
    _ => return None
  }
  if result.timed_out || result.exit_code != 0 {
    return None
  }
  Some((result.wall_us * 1000.0).to_int64())
}

///|
/// The scaling diagnostic is a single-shot comparison at K = 10 and K = 20, so
/// one noisy invocation can produce a false "optimizer elimination" verdict.
/// Take the median of three shots per side: the threshold is unchanged, the
/// measurement is not a coin flip.
async fn scaling_median_ns(
  state : RunState,
  dataset_path : String,
  params_path : String,
  output_dir : String,
  workload : @manifest.Workload,
  repeat : Int32,
) -> Int64? {
  let samples : Array[Int64] = []
  for _ in 0..<3 {
    match
      scaling_wall_ns(
        state, dataset_path, params_path, output_dir, workload, repeat,
      ) {
      Some(value) => samples.push(value)
      None => ()
    }
  }
  if samples.length() == 0 {
    return None
  }
  samples.sort()
  Some(samples[samples.length() / 2])
}

///|
pub async fn run_workload(
  manifest_path : String,
  out_dir : String,
  data_dir : String,
  repo_root : String,
) -> (@artifact.Artifact, String, String) {
  let manifest_path = @fs.realpath(manifest_path) catch { _ => manifest_path }
  let repo_root = @fs.realpath(repo_root) catch { _ => repo_root }
  @fs.mkdir(out_dir, recursive=true, allow_exist=true) catch {
    _ => ()
  }
  @fs.mkdir(data_dir, recursive=true, allow_exist=true) catch {
    _ => ()
  }
  let out_dir = @fs.realpath(out_dir) catch { _ => out_dir }
  let data_dir = @fs.realpath(data_dir) catch { _ => data_dir }
  let workload = @manifest.load_workload(manifest_path)

  let data = @dataset.generate(
    workload.dataset.generator,
    workload.dataset.count,
    workload.dataset.seed,
    workload.dataset.params,
  ) catch {
    @dataset.DatasetError::Message(message) => raise @host.error(message)
  }
  let data_hash = @dataset.sha256_hex(data)
  let dataset_path = join(
    data_dir,
    workload.name +
    "-" +
    workload.dataset.generator +
    "-" +
    workload.dataset.count.to_string() +
    "-" +
    workload.dataset.seed.to_string() +
    "-" +
    @dataset.params_digest(workload.dataset.params) +
    ".bin",
  )
  let dataset_exists = @fs.exists(dataset_path) catch { _ => false }
  if dataset_exists {
    let existing = @fs.read_file(dataset_path) catch {
      _ => raise @host.error("cannot read dataset " + dataset_path)
    }
    let existing_hash = @dataset.sha256_hex(existing.binary())
    if existing_hash != data_hash {
      raise @host.error("dataset cache hash mismatch: " + dataset_path)
    }
  } else {
    @fs.write_file(dataset_path, data) catch {
      _ => raise @host.error("cannot write dataset " + dataset_path)
    }
  }

  let params_path = join(out_dir, "params.txt")
  @fs.write_file(params_path, params_text(workload.params)) catch {
    _ => raise @host.error("cannot write params file")
  }

  let started_at = utc_stamp("%Y-%m-%dT%H:%M:%SZ", repo_root)
  let compact = utc_stamp("%Y%m%dT%H%M%SZ", repo_root)
  let source = source_record(repo_root)
  let commit12 = if source.commit.length() >= 12 {
    source.commit[:12].to_owned()
  } else {
    "nogit"
  }
  let manifest_bytes = @fs.read_file(manifest_path).binary() catch {
    _ => raise @host.error("cannot read manifest " + manifest_path)
  }
  let manifest_sha256 = @dataset.sha256_hex(manifest_bytes)

  let reference_id = workload.verify.reference.unwrap_or("")
  let states : Array[RunState] = []
  for implementation in workload.implementations {
    let build = build_implementation(implementation, out_dir) catch {
      error => raise @host.error("build failed: " + error.to_string())
    }
    states.push({
      implementation,
      toolchain: toolchain_for(implementation),
      build,
      correctness: {
        ok: false,
        mode: workload.verify.mode,
        checked_against: None,
        values: Map([]),
        errors: ["correctness not run"],
      },
      samples_ns: [],
      summary: None,
      measurement_error: None,
      setup: None,
    })
  }

  let mut reference_index : Int32? = None
  for index in 0..<states.length() {
    if states[index].implementation.id == reference_id {
      reference_index = Some(index)
    }
  }
  let reference_index = match reference_index {
    Some(index) => index
    None => raise @host.error("reference implementation not found")
  }
  if states[reference_index].build.ok {
    verify_implementation(
      states[reference_index],
      dataset_path,
      params_path,
      out_dir,
      None,
      workload,
      workload.measurement.timeout_s,
    )
  } else {
    states[reference_index].correctness = {
      ok: false,
      mode: workload.verify.mode,
      checked_against: None,
      values: Map([]),
      errors: ["build failed"],
    }
  }
  let reference_values = if states[reference_index].build.ok &&
    states[reference_index].correctness.ok {
    Some(states[reference_index].correctness.values)
  } else {
    None
  }
  for index in 0..<states.length() {
    if index != reference_index {
      if states[index].build.ok {
        verify_implementation(
          states[index],
          dataset_path,
          params_path,
          out_dir,
          reference_values,
          workload,
          workload.measurement.timeout_s,
        )
      } else {
        states[index].correctness = {
          ok: false,
          mode: workload.verify.mode,
          checked_against: None,
          values: Map([]),
          errors: ["build failed"],
        }
      }
    }
  }

  let valid = states.filter(fn(state) { state.build.ok && state.correctness.ok })
  for state in valid {
    run_setup_baseline(state, dataset_path, params_path, out_dir, workload)
  }
  for _ in 0..<workload.measurement.warmup {
    for state in valid {
      let output_path = join(out_dir, state.implementation.id + "-warmup.json")
      let _ = adapter_run(
        state.implementation,
        dataset_path,
        params_path,
        output_path,
        workload.measurement.inner_repeats,
        workload.measurement.timeout_s,
      ) catch {
        error => raise @host.error("warmup failed: " + error.to_string())
      }
    }
  }
  for round in 0..<workload.measurement.repeats {
    for index in 0..<valid.length() {
      let rotated = (round + index) % valid.length()
      match
        run_measurement(
          valid[rotated],
          dataset_path,
          params_path,
          out_dir,
          workload,
          round,
        ) {
        Some(error) =>
          if valid[rotated].measurement_error is None {
            valid[rotated].measurement_error = Some(error)
          }
        None => ()
      }
    }
  }
  for state in valid {
    state.summary = @measure.summarize(state.samples_ns)
  }

  let scaling_notes : Array[String] = []
  let mut scaling_failed = false
  for state in valid {
    if state.measurement_error is Some(_) {
      continue
    }
    match state.summary {
      Some(summary) => {
        let t10 = scaling_median_ns(
          state, dataset_path, params_path, out_dir, workload, 10,
        )
        let t20 = scaling_median_ns(
          state, dataset_path, params_path, out_dir, workload, 20,
        )
        match (t10, t20) {
          (Some(t10), Some(t20)) => {
            let slope = (t20.to_double() - t10.to_double()) / 10.0
            let ratio = slope / summary.median_ns
            scaling_notes.push(
              "K scaling " +
              state.implementation.id +
              ": K=10 -> 20 slope ratio " +
              ratio.to_string(),
            )
            if ratio < 0.5 {
              scaling_notes.push(
                "optimizer elimination suspected: " + state.implementation.id,
              )
              scaling_failed = true
            }
          }
          _ => {
            scaling_notes.push(
              "K scaling diagnostic unavailable: " + state.implementation.id,
            )
            scaling_failed = true
          }
        }
      }
      None => {
        scaling_notes.push(
          "K scaling needs samples: " + state.implementation.id,
        )
        scaling_failed = true
      }
    }
  }

  let notes : Array[String] = []
  let mut verdict_status = "ok"
  for state in states {
    if !state.build.ok {
      notes.push("build failed: " + state.implementation.id)
      verdict_status = "invalid"
    }
    if !state.correctness.ok {
      notes.push("correctness failed: " + state.implementation.id)
      verdict_status = "invalid"
    }
    if state.measurement_error is Some(error) {
      notes.push(
        "measurement failed: " + state.implementation.id + ": " + error,
      )
      verdict_status = "invalid"
    }
    match state.summary {
      Some(summary) =>
        if summary.cv > workload.measurement.max_cv {
          notes.push(
            "coefficient of variation " +
            summary.cv.to_string() +
            " exceeds max_cv " +
            workload.measurement.max_cv.to_string() +
            ": " +
            state.implementation.id,
          )
          if verdict_status == "ok" {
            verdict_status = "unstable"
          }
        }
      None => ()
    }
  }

  for note in scaling_notes {
    notes.push(note)
  }
  if scaling_failed {
    verdict_status = "invalid"
  }

  let comparisons : Array[@artifact.ComparisonRecord] = []
  if verdict_status == "ok" {
    match states[reference_index].summary {
      Some(reference_summary) =>
        for state in states {
          if state.implementation.id == reference_id {
            continue
          }
          match state.summary {
            Some(summary) =>
              comparisons.push({
                baseline: reference_id,
                subject: state.implementation.id,
                baseline_ns: reference_summary.median_ns,
                subject_ns: summary.median_ns,
                ratio: summary.median_ns / reference_summary.median_ns,
                delta_pct: (
                  summary.median_ns / reference_summary.median_ns - 1.0
                ) *
                100.0,
              })
            None => ()
          }
        }
      None => ()
    }
  }

  let implementations : Array[@artifact.ImplementationRecord] = []
  for state in states {
    let setup = match state.setup {
      Some(setup) =>
        match state.summary {
          Some(summary) =>
            Some(
              (
                {
                  wall_ns: setup.wall_ns,
                  fraction: setup.wall_ns.to_double() /
                  (
                    setup.wall_ns.to_double() +
                    workload.measurement.inner_repeats.to_double() *
                    summary.median_ns
                  ),
                  runs: setup.runs,
                } : @artifact.SetupRecord),
            )
          None => Some(setup)
        }
      None => None
    }
    implementations.push({
      id: state.implementation.id,
      language: state.implementation.language,
      reference: state.implementation.id == reference_id,
      toolchain: state.toolchain,
      build: state.build,
      correctness: state.correctness,
      samples_ns: state.samples_ns,
      summary: state.summary,
      measurement_ok: if state.measurement_error is Some(_) {
        Some(false)
      } else if state.build.ok && state.correctness.ok {
        Some(true)
      } else {
        None
      },
      measurement_error: state.measurement_error,
      setup,
    })
  }

  let finished_at = utc_stamp("%Y-%m-%dT%H:%M:%SZ", repo_root)
  let environment = environment_record()
  let artifact : @artifact.Artifact = {
    id: compact + "-" + commit12,
    started_at,
    finished_at,
    source,
    workload_name: workload.name,
    workload_version: workload.version,
    tier: workload.tier,
    manifest_sha256,
    dataset: {
      generator: workload.dataset.generator,
      count: workload.dataset.count,
      seed: workload.dataset.seed,
      params: dataset_params_json(workload.dataset.params),
      sha256: data_hash,
      bytes: data.length(),
    },
    params: params_json(workload.params),
    measurement: {
      warmup: workload.measurement.warmup,
      repeats: workload.measurement.repeats,
      timeout_s: workload.measurement.timeout_s,
      inner_repeats: workload.measurement.inner_repeats,
      max_cv: workload.measurement.max_cv,
    },
    environment,
    reproduce_command: "cd moonperf && moon run cli --target native -- run ../workloads/" +
    workload.name +
    " --out ../results/tmp/repro --data-dir ../.data --repo-root ..",
    implementations,
    comparisons,
    verdict_status,
    verdict_notes: notes,
  }
  let artifact_path = join(out_dir, artifact.id + ".json")
  let report_path = join(out_dir, artifact.id + ".md")
  @fs.write_file(artifact_path, artifact.to_json().stringify(indent=2) + "\n") catch {
    _ => raise @host.error("cannot write artifact " + artifact_path)
  }
  @fs.write_file(
    report_path,
    @report.render(artifact, workload.summary.unwrap_or("")),
  ) catch {
    _ => raise @host.error("cannot write report " + report_path)
  }
  (artifact, artifact_path, report_path)
}

///|
async fn utc_stamp(format : String, repo_root : String) -> String {
  let stamp = capture_stdout("date", ["-u", "+" + format], repo_root)
  if stamp.length() == 0 {
    abort("cannot read UTC time")
  }
  stamp
}
