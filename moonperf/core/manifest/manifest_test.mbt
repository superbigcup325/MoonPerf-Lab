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

///|
test "nullable-columns manifest is parsed" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"nullable-columns\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="value_min = 0\nvalue_max = 100\nnull_percent = 10",
    )
  let workload = @manifest.parse_manifest_text("demo-scan", text) catch {
    _ => abort("nullable-columns manifest was rejected")
  }
  inspect(workload.dataset.generator, content="nullable-columns")
  inspect(
    @dataset.param_int(workload.dataset.params, "null_percent").unwrap(),
    content="10",
  )
}

///|
test "nullable-columns rejects null_percent above 100" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"nullable-columns\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="value_min = 0\nvalue_max = 100\nnull_percent = 101",
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
test "columnar-gather manifest is parsed" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"columnar-gather\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="value_min = 0\nvalue_max = 100\nlocality = 16",
    )
  let workload = @manifest.parse_manifest_text("demo-scan", text) catch {
    _ => abort("columnar-gather manifest was rejected")
  }
  inspect(workload.dataset.generator, content="columnar-gather")
  inspect(
    @dataset.param_int(workload.dataset.params, "locality").unwrap(),
    content="16",
  )
}

///|
test "csv-records manifest is parsed" {
  let text = valid_manifest
    .replace(
      old="generator = \"uniform-f64\"",
      new="generator = \"csv-records\"",
    )
    .replace(
      old="min = -1.0\nmax = 1.0",
      new="categories = 16\namount_max = 1000000",
    )
  let workload = @manifest.parse_manifest_text("demo-scan", text) catch {
    _ => abort("csv-records manifest was rejected")
  }
  inspect(workload.dataset.generator, content="csv-records")
  inspect(
    @dataset.param_int(workload.dataset.params, "categories").unwrap(),
    content="16",
  )
}

///|
let matrix_manifest : String = valid_manifest +
  "\n" +
  (
    #|[matrix.half]
    #|status = "probe"
    #|description = "Half the values, same distribution."
    #|count = 8
    #|
    #|[matrix.half.dataset_params]
    #|min = 0.0
    #|
    #|[matrix.tiny]
    #|status = "rejected"
    #|description = "Too short to say anything."
    #|seed = 7
  )

///|
test "input matrix is parsed and merges over the recorded dataset" {
  let workload = @manifest.parse_manifest_text("demo-scan", matrix_manifest) catch {
    _ => abort("manifest with a matrix was rejected")
  }
  inspect(workload.matrix.length(), content="2")
  // Names are sorted, so the matrix reads the same in every output.
  inspect(workload.matrix[0].name, content="half")
  inspect(workload.matrix[0].status, content="probe")
  inspect(workload.matrix[1].name, content="tiny")
  let half = @manifest.variant_dataset(workload, "half") catch {
    _ => abort("declared variant was not found")
  }
  inspect(half.count, content="8")
  inspect(half.seed, content="1")
  inspect(@dataset.param_float(half.params, "min").unwrap(), content="0")
  inspect(@dataset.param_float(half.params, "max").unwrap(), content="1")
  let tiny = @manifest.variant_dataset(workload, "tiny") catch {
    _ => abort("declared variant was not found")
  }
  inspect(tiny.count, content="16")
  inspect(tiny.seed, content="7")
}

///|
test "unknown variant names are reported with the declared ones" {
  let workload = @manifest.parse_manifest_text("demo-scan", matrix_manifest) catch {
    _ => abort("manifest with a matrix was rejected")
  }
  let message = try {
    ignore(@manifest.variant_dataset(workload, "wide"))
    "no failure"
  } catch {
    @manifest.ManifestError::Message(text) => text
  }
  inspect(
    message,
    content="demo-scan: unknown variant 'wide'; declared: half, tiny",
  )
}

///|
test "a manifest without a matrix declares no variants" {
  let workload = @manifest.parse_manifest_text("demo-scan", valid_manifest) catch {
    _ => abort("valid manifest was rejected")
  }
  inspect(workload.matrix.length(), content="0")
  let message = try {
    ignore(@manifest.variant_dataset(workload, "half"))
    "no failure"
  } catch {
    @manifest.ManifestError::Message(text) => text
  }
  inspect(message, content="demo-scan: declares no input matrix")
}

///|
fn matrix_failure(block : String) -> String {
  let text = valid_manifest + "\n" + block
  try {
    ignore(@manifest.parse_manifest_text("demo-scan", text))
    "no failure"
  } catch {
    @manifest.ManifestError::Message(message) => message
  }
}

///|
test "a variant must override something" {
  inspect(
    matrix_failure(
      (
        #|[matrix.empty]
        #|status = "probe"
        #|description = "Nothing changes."
      ),
    ),
    content="matrix.empty must override at least one of count, seed or dataset_params",
  )
}

///|
test "a variant must differ from the recorded dataset" {
  inspect(
    matrix_failure(
      (
        #|[matrix.same]
        #|status = "probe"
        #|description = "Same as the recorded configuration."
        #|count = 16
        #|seed = 1
        #|[matrix.same.dataset_params]
        #|min = -1.0
        #|max = 1.0
      ),
    ),
    content="matrix.same must differ from the recorded [dataset] configuration",
  )
}

///|
test "a variant must stay a legal dataset of the same generator" {
  inspect(
    matrix_failure(
      (
        #|[matrix.inverted]
        #|status = "probe"
        #|description = "An inverted range is not a uniform-f64 dataset."
        #|[matrix.inverted.dataset_params]
        #|min = 1.0
        #|max = -1.0
      ),
    ),
    content="matrix.inverted: dataset.params.min must be below dataset.params.max",
  )
}

///|
test "variant names must be identifiers" {
  inspect(
    matrix_failure(
      (
        #|[matrix."Half"]
        #|status = "probe"
        #|description = "Upper case is not an identifier."
        #|count = 8
      ),
    ),
    content="matrix.Half: variant names must match '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'",
  )
}

///|
test "a variant status must be probe or rejected" {
  inspect(
    matrix_failure(
      (
        #|[matrix.maybe]
        #|status = "maybe"
        #|description = "Not a declared status."
        #|count = 8
      ),
    ),
    content="matrix.maybe.status must be one of probe, rejected, got maybe",
  )
}
