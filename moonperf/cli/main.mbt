///|
fn usage() -> Unit {
  println(
    "usage: mpf <list|validate|dataset> [options]\n" +
    "  list [root]                         list workloads under root\n" +
    "  validate [path ...]                 validate workloads or manifests\n" +
    "  dataset --manifest FILE --out FILE  generate a workload dataset",
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
  let workload = @manifest.load_workload(manifest) catch {
    @manifest.ManifestError::Message(message) => abort(message)
  }
  let data = @dataset.uniform_f64_bytes(
    workload.dataset.count,
    workload.dataset.seed,
    workload.dataset.min_value,
    workload.dataset.max_value,
  )
  @fs.write_file(out, data) catch {
    _ => abort("cannot write " + out)
  }
  let hash = @dataset.sha256_hex(data)
  println(
    "{\"name\":\"\{workload.name}\",\"count\":\{workload.dataset.count},\"seed\":\{workload.dataset.seed},\"sha256\":\"\{hash}\",\"bytes\":\{data.length()}}",
  )
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
  } else {
    usage()
    abort("unknown command: " + command)
  }
}
