///|
test "artifact serializes the required shape" {
  let summary = @measure.make_summary(1, 10L, 10.0, 10.0, 0.0, 0.0)
  let artifact : Artifact = {
    id: "20261020T000000Z-abcdef123456",
    started_at: "2026-10-20T00:00:00Z",
    finished_at: "2026-10-20T00:01:00Z",
    source: { commit: "abcdef123456", dirty: false, branch: "main", },
    workload_name: "numeric-scan",
    workload_version: 1,
    tier: "micro",
    manifest_sha256: "a".repeat(64),
    dataset: {
      generator: "uniform-f64",
      count: 16,
      seed: 1L,
      params: Map([("min", Json::number(-1.0)), ("max", Json::number(1.0))]),
      sha256: "b".repeat(64),
      bytes: 128,
    },
    params: Map([("threshold", Json::number(0.0))]),
    measurement: {
      warmup: 1,
      repeats: 2,
      timeout_s: 10.0,
      inner_repeats: 1,
      max_cv: 0.05,
    },
    environment: {
      os: "Linux",
      os_release: "test",
      arch: "x86_64",
      cpu_model: "test cpu",
      logical_cpus: 4,
      governor: Some("performance"),
      memory_bytes: 1024L,
    },
    reproduce_command: "mpf run workloads/numeric-scan",
    implementations: [
      {
        id: "alpha",
        language: "MoonBit",
        reference: true,
        toolchain: Some("moon test"),
        build: {
          ok: true,
          skipped: false,
          command: Some("./build.sh"),
          duration_ms: 1.0,
          log_sha256: None,
        },
        correctness: {
          ok: true,
          mode: "exact",
          checked_against: None,
          values: Map([("n", Json::number(16.0))]),
          errors: ([] : Array[String]),
        },
        samples_ns: [10L, 11L],
        summary: Some(summary),
        setup: Some(({ wall_ns: 5L, fraction: 0.05, } : SetupRecord)),
      },
    ],
    comparisons: ([] : Array[ComparisonRecord]),
    verdict_status: "ok",
    verdict_notes: ([] : Array[String]),
  }
  let json = artifact.to_json()
  let text = json.stringify()
  inspect(text.contains("\"schema_version\":1"), content="true")
  inspect(text.contains("\"name\":\"numeric-scan\""), content="true")
  inspect(text.contains("\"inner_repeats\":0"), content="true")
  inspect(text.contains("\"samples_ns\":[10,11]"), content="true")
}
