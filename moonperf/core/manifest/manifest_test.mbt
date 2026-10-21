///|
let valid_manifest : String =
  #|schema_version = 1
  #|name = "demo-scan"
  #|version = 1
  #|status = "draft"
  #|tier = "micro"
  #|summary = "test workload"
  #|
  #|[dataset]
  #|generator = "uniform-f64"
  #|count = 16
  #|seed = 1
  #|
  #|[dataset.params]
  #|min = -1.0
  #|max = 1.0
  #|
  #|[params]
  #|threshold = 0.0
  #|
  #|[verify]
  #|mode = "tolerance"
  #|reference = "alpha"
  #|rtol = 1.0e-9
  #|fields = ["n", "sum"]
  #|
  #|[measurement]
  #|warmup = 1
  #|repeats = 2
  #|timeout_s = 10
  #|inner_repeats = 1
  #|max_cv = 0.05

///|
test "valid manifest is parsed" {
  let workload = @manifest.parse_manifest_text("demo-scan", valid_manifest) catch {
    _ => abort("valid manifest was rejected")
  }
  inspect(workload.name, content="demo-scan")
  inspect(workload.version, content="1")
  inspect(workload.dataset.count, content="16")
  inspect(
    @dataset.param_float(workload.dataset.params, "min").unwrap(),
    content="-1",
  )
  inspect(workload.verify.mode, content="tolerance")
  inspect(workload.verify.fields.length(), content="2")
  inspect(workload.measurement.max_cv, content="0.05")
}

///|
test "manifest name must match the directory" {
  let failed = try {
    ignore(@manifest.parse_manifest_text("other-scan", valid_manifest))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "tolerance mode requires rtol" {
  let text = valid_manifest.replace(old="rtol = 1.0e-9\n", new="")
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "unknown tier is rejected" {
  let text = valid_manifest.replace(
    old="tier = \"micro\"",
    new="tier = \"tiny\"",
  )
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "uniform-f64 requires min below max" {
  let text = valid_manifest.replace(old="min = -1.0", new="min = 2.0")
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "structured-records manifest is parsed" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"structured-records\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="key_bits = 8\npayload_min = 0\npayload_max = 100",
    )
  let workload = @manifest.parse_manifest_text("demo-scan", text) catch {
    _ => abort("structured-records manifest was rejected")
  }
  inspect(workload.dataset.generator, content="structured-records")
  inspect(
    @dataset.param_int(workload.dataset.params, "key_bits").unwrap(),
    content="8",
  )
}

///|
test "unknown generator is rejected" {
  let text = valid_manifest.replace(
    old="generator = \"uniform-f64\"",
    new="generator = \"made-up\"",
  )
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "structured-records rejects an out-of-range key_bits" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"structured-records\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="key_bits = 0\npayload_min = 0\npayload_max = 100",
    )
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}

///|
test "strings manifest is parsed" {
  let text = valid_manifest
    .replace(old="generator = \"uniform-f64\"", new="generator = \"strings\"")
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="distinct = 64\nvalue_len_min = 4\nvalue_len_max = 12\nskew = 3",
    )
  let workload = @manifest.parse_manifest_text("demo-scan", text) catch {
    _ => abort("strings manifest was rejected")
  }
  inspect(workload.dataset.generator, content="strings")
  inspect(
    @dataset.param_int(workload.dataset.params, "distinct").unwrap(),
    content="64",
  )
}

///|
test "strings rejects an inverted length range" {
  let text = valid_manifest
    .replace(old="generator = \"uniform-f64\"", new="generator = \"strings\"")
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="distinct = 64\nvalue_len_min = 8\nvalue_len_max = 4\nskew = 3",
    )
  let failed = try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    false
  } catch {
    @manifest.ManifestError::Message(_) => true
  }
  inspect(failed, content="true")
}
