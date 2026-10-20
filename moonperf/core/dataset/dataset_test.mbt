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
