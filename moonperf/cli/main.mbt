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
fn toml_number(value : @toml.TomlValue) -> Double {
  match value {
    @toml.TomlFloat(number) => number
    @toml.TomlInteger(number) => number.to_double()
    _ => abort("expected a number")
  }
}

///|
fn required_table(
  table : Map[String, @toml.TomlValue],
  key : String,
) -> Map[String, @toml.TomlValue] {
  match table.get(key) {
    Some(@toml.TomlTable(inner)) => inner
    _ => abort("missing table " + key)
  }
}

///|
async fn main {
  let args = @env.args()
  let manifest = option(args, "--manifest")
  let out = option(args, "--out")

  let text = @fs.read_file(manifest).text() catch {
    _ => abort("cannot read " + manifest)
  }
  let root = @toml.parse(text) catch {
    error => abort("invalid TOML: " + error.to_string())
  }
  let table = match root {
    @toml.TomlTable(table) => table
    _ => abort("manifest root must be a table")
  }
  let name = match table.get("name") {
    Some(@toml.TomlString(name)) => name
    _ => abort("manifest: missing name")
  }
  let dataset = required_table(table, "dataset")
  let generator = match dataset.get("generator") {
    Some(@toml.TomlString(generator)) => generator
    _ => abort("manifest: missing dataset.generator")
  }
  if generator != "uniform-f64" {
    abort("unsupported generator " + generator)
  }
  let count = match dataset.get("count") {
    Some(@toml.TomlInteger(count)) => count.to_int()
    _ => abort("manifest: missing dataset.count")
  }
  let seed = match dataset.get("seed") {
    Some(@toml.TomlInteger(seed)) => seed
    _ => abort("manifest: missing dataset.seed")
  }
  let params = required_table(dataset, "params")
  let min = match params.get("min") {
    Some(value) => toml_number(value)
    None => abort("manifest: missing dataset.params.min")
  }
  let max = match params.get("max") {
    Some(value) => toml_number(value)
    None => abort("manifest: missing dataset.params.max")
  }

  let data = @dataset.uniform_f64_bytes(count, seed, min, max)
  @fs.write_file(out, data) catch {
    _ => abort("cannot write " + out)
  }
  let hash = @dataset.sha256_hex(data)
  println(
    "{\"name\":\"\{name}\",\"count\":\{count},\"seed\":\{seed},\"sha256\":\"\{hash}\",\"bytes\":\{data.length()}}",
  )
}
