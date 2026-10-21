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

///|
test "strings small deterministic bytes" {
  let data = @dataset.strings_bytes(6, 1L, 4, 3, 5, 2)
  inspect(
    @crypto.bytes_to_hex_string(data),
    content="0400000005000000746f646663030000006c797303000000657979040000006c706273000000000000000000000000000000000000000002000000",
  )
}

///|
test "strings golden hash" {
  let data = @dataset.strings_bytes(100_000, 20261022L, 10_000, 4, 24, 3)
  inspect(
    @dataset.sha256_hex(data),
    content="76ede39d734ae67e1994654c660d011e57d021d2c3e62be1577496d371116681",
  )
}

///|
test "nullable-column small deterministic bytes" {
  let data = @dataset.nullable_column_bytes(10, 1L, 0L, 9L, 50)
  inspect(
    @crypto.bytes_to_hex_string(data),
    content="0a00000009000000000000000500000000000000080000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000010000000000000000000000000000004701",
  )
}

///|
test "nullable-column golden hash" {
  let data = @dataset.nullable_column_bytes(
    100_000, 20261023L, 0L, 1_000_000L, 10,
  )
  inspect(
    @dataset.sha256_hex(data),
    content="d57afd010d9ac41fb516b2879201971fe1e960c25f6a76afcc31b13de57bda93",
  )
}

///|
test "columnar-gather small deterministic bytes" {
  let data = @dataset.columnar_gather_bytes(8, 1L, 0L, 99L, 2)
  inspect(
    @crypto.bytes_to_hex_string(data),
    content="08000000410000000000000013000000000000005a0000000000000023000000000000003d0000000000000030000000000000002d0000000000000021000000000000000100000002000000040000000500000001000000020000000200000003000000",
  )
}

///|
test "columnar-gather golden hash" {
  let data = @dataset.columnar_gather_bytes(
    1_000_000, 20261025L, 0L, 1_000_000L, 16,
  )
  inspect(
    @dataset.sha256_hex(data),
    content="e99550ab9f5c8e5d289cdfb90f9ca4303df495a6afc79b106a0b84a5b5361e79",
  )
}

///|
test "csv-records small deterministic bytes" {
  let data = @dataset.csv_records_bytes(5, 1L, 4, 99L)
  inspect(
    @utf8.decode(data),
    content="id,category,amount\n0,1,19\n1,2,35\n2,1,48\n3,1,33\n4,0,50\n",
  )
}

///|
test "csv-records golden hash" {
  let data = @dataset.csv_records_bytes(100_000, 20261026L, 16, 1_000_000L)
  inspect(
    @dataset.sha256_hex(data),
    content="d9bad5505aec0b089a00aebd2a7591a7ae2654f9270949917b30f1950d8afeb3",
  )
}
