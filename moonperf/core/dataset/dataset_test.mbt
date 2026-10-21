///|
test "uniform-f64 small deterministic bytes" {
  let data = @dataset.uniform_f64_bytes(2, 1L, -1.0, 1.0)
  inspect(
    @crypto.bytes_to_hex_string(data),
    content="580289ec2d0ac13f74c7b2d0c675df3f",
  )
}

///|
test "uniform-f64 numeric-scan golden hash" {
  let data = @dataset.uniform_f64_bytes(1_000_000, 20261020L, -1.0, 1.0)
  inspect(
    @dataset.sha256_hex(data),
    content="fa49700b3b7bac4b840d944268bdc82291906c703a83a04cc57917c87a0a8fc2",
  )
}

///|
test "structured-records small deterministic bytes" {
  let data = @dataset.structured_records_bytes(2, 1L, 8L, 0L, 100L)
  inspect(
    @crypto.bytes_to_hex_string(data),
    content="91000000000000002300000000000000f8000000000000004b00000000000000",
  )
}

///|
test "structured-records golden hash" {
  let data = @dataset.structured_records_bytes(
    1_000_000, 20261021L, 20L, 0L, 1_000_000L,
  )
  inspect(
    @dataset.sha256_hex(data),
    content="a0bf64a4d028cc768a1ce138b7b4bf7cd9bd6a57244bd51c5996575682eba13c",
  )
}

///|
test "param digest is order independent" {
  let forward : Map[String, @dataset.ParamValue] = Map([
    ("min", @dataset.ParamValue::Float(-1.0)),
    ("max", @dataset.ParamValue::Int(1L)),
  ])
  let backward : Map[String, @dataset.ParamValue] = Map([
    ("max", @dataset.ParamValue::Int(1L)),
    ("min", @dataset.ParamValue::Float(-1.0)),
  ])
  inspect(@dataset.params_digest(forward).length(), content="8")
  inspect(
    @dataset.params_digest(forward) == @dataset.params_digest(backward),
    content="true",
  )
  inspect(
    @dataset.params_digest(forward) ==
    @dataset.params_digest(
      Map([
        ("min", @dataset.ParamValue::Float(-2.0)),
        ("max", @dataset.ParamValue::Int(1L)),
      ]),
    ),
    content="false",
  )
}
