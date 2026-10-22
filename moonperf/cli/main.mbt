///|
fn usage() -> Unit {
  println(
    "usage: mpf <list|validate|dataset|history|run|report> [options]\n" +
    "  list [root]                         list workloads under root\n" +
    "  validate [path ...]                 validate workloads or manifests\n" +
    "  dataset --manifest FILE|DIR --out FILE [--variant NAME]\n" +
    "                                      generate a workload dataset\n" +
    "  history DIR [--check]              build or verify a results index and trend\n" +
    "  run WORKLOAD [--out DIR] [--data-dir DIR] [--repo-root DIR]\n" +
    "  report ARTIFACT [--out FILE] [--repo-root DIR]",
  )
}

///|
fn option(args : Array[String], name : String) -> String {
  let mut index = 0
  while index + 1 < args.length() {
    if args[index] == name {
      return args[index + 1]
    }
    index = index + 1
  }
  abort("missing " + name)
}

///|
fn option_or(args : Array[String], name : String, fallback : String) -> String {
  let mut index = 0
  while index + 1 < args.length() {
    if args[index] == name {
      return args[index + 1]
    }
    index = index + 1
  }
  fallback
}

///|
fn workload_manifest(path : String) -> String {
  if path.has_suffix("workload.toml") {
    path
  } else {
    @manifest.join(path, "workload.toml")
  }
}

///|
async fn default_workloads_root() -> String {
  if (@fs.exists("../workloads") catch { _ => false }) {
    "../workloads"
  } else {
    "workloads"
  }
}

///|
fn print_workload(workload : @manifest.Workload) -> Unit {
  let mut implementations = ""
  for implementation in workload.implementations {
    if implementations.length() > 0 {
      implementations = implementations + ", "
    }
    implementations = implementations + implementation.id
  }
  if implementations.length() == 0 {
    implementations = "-"
  }
  println(
    workload.name +
    "\t" +
    workload.version.to_string() +
    "\t" +
    workload.tier +
    "\t" +
    workload.status +
    "\t" +
    implementations,
  )
}

///|
async fn list(args : Array[String]) -> Unit {
  let root = if args.length() >= 3 { args[2] } else { default_workloads_root() }
  let paths = @manifest.discover_workload_paths(root)
  if paths.length() == 0 {
    abort("no workload manifests under " + root)
  }
  println("WORKLOAD\tVERSION\tTIER\tSTATUS\tIMPLEMENTATIONS")
  let mut failures = 0
  for path in paths {
    let workload = @manifest.load_workload(path) catch {
      @manifest.ManifestError::Message(message) => {
        failures = failures + 1
        println("<invalid>\t-\t-\t-\t" + message)
        continue
      }
    }
    print_workload(workload)
  }
  if failures > 0 {
    abort("validation failed")
  }
}

///|
async fn validate_paths(argument : String) -> Array[String] {
  if argument.has_suffix("workload.toml") {
    return [argument]
  }
  let candidate = @manifest.join(argument, "workload.toml")
  if (@fs.exists(candidate) catch { _ => false }) {
    return [candidate]
  }
  @manifest.discover_workload_paths(argument)
}

///|
async fn validate(args : Array[String]) -> Unit {
  let paths : Array[String] = []
  if args.length() > 2 {
    for index in 2..<args.length() {
      for path in validate_paths(args[index]) {
        paths.push(path)
      }
    }
  } else {
    for path in @manifest.discover_workload_paths(default_workloads_root()) {
      paths.push(path)
    }
  }
  if paths.length() == 0 {
    abort("nothing to validate")
  }
  let mut failures = 0
  for path in paths {
    let workload = @manifest.load_workload(path) catch {
      @manifest.ManifestError::Message(message) => {
        failures = failures + 1
        println("FAIL " + path)
        println("     " + message)
        continue
      }
    }
    println(
      "ok   " +
      workload.name +
      " v" +
      workload.version.to_string() +
      " (" +
      workload.status +
      ", " +
      workload.tier +
      ", implementations: " +
      (if workload.implementations.length() == 0 {
        "none"
      } else {
        let mut ids = ""
        for implementation in workload.implementations {
          if ids.length() > 0 {
            ids = ids + ", "
          }
          ids = ids + implementation.id
        }
        ids
      }) +
      ")",
    )
  }
  if failures > 0 {
    abort("validation failed")
  }
}

///|
async fn dataset(args : Array[String]) -> Unit {
  let manifest = option(args, "--manifest")
  let out = option(args, "--out")
  let variant = option_or(args, "--variant", "")
  let workload = @manifest.load_workload(workload_manifest(manifest)) catch {
    @manifest.ManifestError::Message(message) => abort(message)
  }
  let config = if variant == "" {
    workload.dataset
  } else {
    @manifest.variant_dataset(workload, variant) catch {
      @manifest.ManifestError::Message(message) => abort(message)
    }
  }
  let data = @dataset.generate(
    config.generator,
    config.count,
    config.seed,
    config.params,
  ) catch {
    @dataset.DatasetError::Message(message) => abort(message)
  }
  @fs.write_file(out, data) catch {
    _ => abort("cannot write " + out)
  }
  let hash = @dataset.sha256_hex(data)
  println(
    "{\"name\":\"\{workload.name}\",\"variant\":\"\{variant}\",\"generator\":\"\{config.generator}\",\"count\":\{config.count},\"seed\":\{config.seed},\"sha256\":\"\{hash}\",\"bytes\":\{data.length()}}",
  )
}

///|
async fn run(args : Array[String]) -> Unit {
  let workload = if args.length() >= 3 && !args[2].has_prefix("--") {
    args[2]
  } else {
    option(args, "--workload")
  }
  let default_root = if (@fs.exists("../workloads") catch { _ => false }) {
    ".."
  } else {
    "."
  }
  let out = option_or(args, "--out", "../results/tmp")
  let data = option_or(args, "--data-dir", "../.data")
  let repo = option_or(args, "--repo-root", default_root)
  let (artifact, artifact_path, report_path) = @runner.run_workload(
    workload_manifest(workload),
    out,
    data,
    repo,
  )
  for implementation in artifact.implementations {
    match implementation.summary {
      Some(summary) =>
        println(
          "  " +
          implementation.id +
          " median " +
          summary.median_ns.to_string() +
          " ns/iter cv " +
          (summary.cv * 100.0).to_string() +
          " %",
        )
      None => println("  " + implementation.id + " excluded")
    }
  }
  println("verdict " + artifact.verdict_status)
  for note in artifact.verdict_notes {
    println("  note: " + note)
  }
  println("artifact " + artifact_path)
  println("report   " + report_path)
  if artifact.verdict_status == "invalid" {
    abort("experiment invalid")
  }
}

///|
/// Build (or verify) one workload's history from its committed artifacts. The
/// index and the trend are derived data: this command reads artifacts and writes
/// two files, and `--check` refuses to write when either is out of date.
async fn history(args : Array[String]) -> Unit {
  let mut directory = if args.length() >= 3 && !args[2].has_prefix("--") {
    args[2]
  } else {
    option(args, "--dir")
  }
  // A trailing slash is a normal way to name a directory and must not change
  // the workload name derived from it.
  while directory.length() > 1 && directory.has_suffix("/") {
    directory = directory[:directory.length() - 1].to_owned()
  }
  let check = args.contains("--check")
  let workload = @manifest.basename(directory)
  if workload.length() == 0 || workload == "." || workload == ".." {
    abort("history: give a workload results directory, got " + directory)
  }
  let names = @fs.readdir(directory, sort=true) catch {
    _ => abort("history: cannot read " + directory)
  }
  let entries : Array[@history.Entry] = []
  for name in names {
    if !name.has_suffix(".json") || name == "index.json" {
      continue
    }
    let path = @manifest.join(directory, name)
    let text = @xfs.read_file_to_string(path) catch {
      _ => abort("history: cannot read " + path)
    }
    let parsed = @json.parse(text) catch {
      _ => abort("history: invalid JSON in " + path)
    }
    let artifact = @artifact.from_json(parsed)
    if artifact.workload_name != workload {
      abort(
        "history: " +
        path +
        " records workload '" +
        artifact.workload_name +
        "', but the directory is '" +
        workload +
        "'",
      )
    }
    entries.push(@history.entry(name, artifact))
  }
  if entries.length() == 0 {
    abort("history: no result artifacts under " + directory)
  }
  let index = @history.build(workload, entries)
  let index_text = index.to_json().stringify(indent=2) + "\n"
  let trend_text = @history.render(index)
  let index_path = @manifest.join(directory, "index.json")
  let trend_path = @manifest.join(directory, "trend.md")
  for
    pair in [
      (index_path, index_text, "index"),
      (trend_path, trend_text, "trend"),
    ] {
    let (path, expected, label) = pair
    if check {
      let actual = @xfs.read_file_to_string(path) catch {
        _ =>
          abort(
            "history: " +
            path +
            " is missing; run `mpf history " +
            directory +
            "`",
          )
      }
      if actual != expected {
        abort(
          "history: " +
          label +
          " is out of date (" +
          path +
          "); run `mpf history " +
          directory +
          "`",
        )
      }
    } else {
      @xfs.write_string_to_file(path, expected) catch {
        _ => abort("history: cannot write " + path)
      }
    }
  }
  for entry in index.entries {
    println(
      "  " +
      entry.id +
      "  " +
      entry.started_at +
      "  " +
      entry.verdict +
      "  v" +
      entry.workload_version.to_string() +
      "  " +
      entry.host_profile,
    )
  }
  if check {
    println(
      "history ok: " +
      entries.length().to_string() +
      (if entries.length() == 1 { " artifact (" } else { " artifacts (" }) +
      workload +
      ")",
    )
  } else {
    println("history " + index_path + " and " + trend_path)
  }
}

///|
async fn report(args : Array[String]) -> Unit {
  let artifact_path = if args.length() >= 3 && !args[2].has_prefix("--") {
    args[2]
  } else {
    option(args, "--artifact")
  }
  let default_root = if (@fs.exists("../workloads") catch { _ => false }) {
    ".."
  } else {
    "."
  }
  let repo_root = option_or(args, "--repo-root", default_root)
  let out = option_or(
    args,
    "--out",
    if artifact_path.has_suffix(".json") {
      artifact_path[:artifact_path.length() - 5].to_owned() + ".md"
    } else {
      artifact_path + ".md"
    },
  )
  let text = @xfs.read_file_to_string(artifact_path) catch {
    _ => abort("cannot read " + artifact_path)
  }
  let parsed = @json.parse(text) catch {
    _ => abort("invalid JSON: " + artifact_path)
  }
  let artifact = @artifact.from_json(parsed)
  let manifest_path = repo_root +
    "/workloads/" +
    artifact.workload_name +
    "/workload.toml"
  let question = @manifest.load_workload(manifest_path).summary.unwrap_or("") catch {
    _ => ""
  }
  @xfs.write_string_to_file(out, @report.render(artifact, question)) catch {
    _ => abort("cannot write " + out)
  }
  println("report " + out)
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let command = args[1]
  if command == "list" {
    list(args)
  } else if command == "validate" {
    validate(args)
  } else if command == "dataset" {
    dataset(args)
  } else if command == "run" {
    run(args)
  } else if command == "report" {
    report(args)
  } else if command == "history" {
    history(args)
  } else {
    usage()
    abort("unknown command: " + command)
  }
}
