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
  inspect(workload.dataset.min_value, content="-1")
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
