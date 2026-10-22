///|
fn test_point(
  id : String,
  median : Double?,
  cv : Double?,
  ok : Bool,
) -> ImplementationPoint {
  {
    id,
    language: "Rust",
    reference: id == "rust",
    median_ns: median,
    cv,
    samples: 20,
    correctness_ok: ok,
  }
}

///|
fn test_entry(
  id : String,
  started_at : String,
  profile : String,
  verdict : String,
  points : Array[ImplementationPoint],
) -> Entry {
  {
    artifact: id + ".json",
    id,
    started_at,
    workload_version: 1,
    tier: "component",
    verdict,
    harness_version: "0.1.1",
    manifest_sha256: "00",
    commit: "b6d5f9215963315c044244df9cad75cffde3e68b",
    branch: "main",
    dirty: false,
    host_profile: profile,
    dataset_generator: "columnar-gather",
    dataset_count: 4000000,
    dataset_seed: 20261025,
    dataset_sha256: "34c2",
    implementations: points,
  }
}

///|
test "slug collapses punctuation and marketing marks" {
  inspect(slug("Intel(R) Core(TM) i5-12500H"), content="intel-core-i5-12500h")
  inspect(slug("  spaced   out  "), content="spaced-out")
  inspect(slug("x86_64"), content="x86-64")
  inspect(slug(""), content="")
}

///|
test "host profile is the identity of the measurement conditions" {
  let environment : @artifact.EnvironmentRecord = {
    os: "Linux",
    os_release: "CachyOS",
    arch: "x86_64",
    cpu_model: "12th Gen Intel(R) Core(TM) i5-12500H",
    logical_cpus: 16,
    governor: Some("powersave"),
    memory_bytes: 16540495872L,
  }
  inspect(
    host_profile(environment),
    content="linux-x86-64-12th-gen-intel-core-i5-12500h-16c-powersave",
  )
  // A governor change is a different measurement condition, so it forks the
  // profile instead of silently joining the table.
  let performance = { ..environment, governor: Some("performance"), }
  inspect(host_profile(performance).has_suffix("-performance"), content="true")
  let unknown = { ..environment, governor: None, }
  inspect(host_profile(unknown).has_suffix("-unknown"), content="true")
}

///|
test "entries are ordered by start time and then by file name" {
  let index = build("demo", [
    test_entry("20261021T120000Z-b", "2026-10-21T12:00:00Z", "host", "ok", []),
    test_entry("20261021T100000Z-a", "2026-10-21T10:00:00Z", "host", "ok", []),
  ])
  inspect(index.entries[0].id, content="20261021T100000Z-a")
  inspect(index.entries[1].id, content="20261021T120000Z-b")
}

///|
test "the trend keeps a failed implementation visible" {
  let index = build("demo", [
    test_entry("20261021T100000Z-a", "2026-10-21T10:00:00Z", "host-a", "ok", [
      test_point("rust", Some(1000.0), Some(0.02), true),
      test_point("moonbit", Some(2000.0), Some(0.05), true),
    ]),
    test_entry(
      "20261021T110000Z-b",
      "2026-10-21T11:00:00Z",
      "host-a",
      "invalid",
      [test_point("rust", None, None, false)],
    ),
  ])
  let text = render(index)
  inspect(text.contains("# demo result history"), content="true")
  inspect(
    text.contains("2 artifacts on 1 host profile, workload v1."),
    content="true",
  )
  inspect(
    text.contains("| `20261021T100000Z-a` | 2026-10-21T10:00:00Z"),
    content="true",
  )
  inspect(text.contains("`b6d5f9215963`"), content="true")
  // A missing measurement is not silently zero, and a failed one is not hidden.
  inspect(text.contains("| invalid | failed | - |"), content="true")
  inspect(text.contains("5 %"), content="true")
  inspect(
    text.contains("a delta without its noise model is not a regression"),
    content="true",
  )
}

///|
test "host profiles are separated, never merged into one table" {
  let index = build("demo", [
    test_entry("20261021T100000Z-a", "2026-10-21T10:00:00Z", "host-a", "ok", [
      test_point("rust", Some(1000.0), Some(0.01), true),
    ]),
    test_entry("20261021T110000Z-b", "2026-10-21T11:00:00Z", "host-b", "ok", [
      test_point("rust", Some(5000.0), Some(0.01), true),
    ]),
  ])
  let text = render(index)
  inspect(text.contains("## host-a"), content="true")
  inspect(text.contains("## host-b"), content="true")
  inspect(text.contains("2 artifacts on 2 host profiles"), content="true")
}

///|
test "an empty history says so instead of rendering an empty table" {
  let text = render(build("demo", []))
  inspect(text.contains("No committed artifact yet."), content="true")
}

///|
test "the index JSON is deterministic and keeps every entry" {
  let index = build("demo", [
    test_entry("20261021T100000Z-a", "2026-10-21T10:00:00Z", "host-a", "ok", [
      test_point("rust", Some(1000.5), Some(0.0125), true),
    ]),
  ])
  let first = index.to_json().stringify(indent=2)
  let second = index.to_json().stringify(indent=2)
  inspect(first, content=second)
  inspect(first.contains("\"schema_version\": 1"), content="true")
  inspect(first.contains("\"workload\": \"demo\""), content="true")
  inspect(first.contains("\"median_ns\": 1000.5"), content="true")
  inspect(first.contains("\"cv\": 0.0125"), content="true")
  inspect(
    first.contains("\"artifact\": \"20261021T100000Z-a.json\""),
    content="true",
  )
}
