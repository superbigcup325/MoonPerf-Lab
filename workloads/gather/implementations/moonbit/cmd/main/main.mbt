//! gather: the MoonBit implementation.
//!
//! The dataset is a `columnar-gather` stream: `u32 row_count`, then
//! `row_count` × `i64` value, then `row_count` × `u32` index. The kernel
//! gathers the value column through the index vector into an output vector and
//! checksums the result.
//!
//! The generator guarantees every index is in `[0, row_count)`, so the kernel
//! does not run a per-row range check: the question here is the gather loop and
//! its locality, not the cost of an error path.

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
/// One gather pass: indirect read into the output vector, then the checksum.
fn gather(
  values : Array[UInt64],
  indices : Array[Int32],
  out : Array[UInt64],
) -> UInt64 {
  let rows = indices.length()
  let mut row = 0
  while row < rows {
    // The generator guarantees 0 <= index < rows.
    out[row] = values.unsafe_get(indices[row])
    row = row + 1
  }
  let mut checksum = 0UL
  let mut position = 0
  while position < rows {
    checksum = checksum + out[position] * (position + 1).to_uint64()
    position = position + 1
  }
  checksum
}

///|
/// A `u64` as 16 lowercase hex digits, so the JSON value is exact.
fn hex16(value : UInt64) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut index = 0
  while index < 16 {
    let shift : Int32 = (15 - index) * 4
    let nibble = ((value >> shift) & 0xFUL).to_int()
    out = out + digits[nibble:nibble + 1].to_owned()
    index = index + 1
  }
  out
}

///|
fn main {
  let args = @env.args()
  let input = option(args, "--input")
  let output = option(args, "--output")
  // The contract passes --params even when the workload declares none.
  let _params = option(args, "--params")
  let repeat = @string.parse_int(option(args, "--repeat")) catch {
    _ => abort("--repeat must be an integer")
  }

  let raw = @fs.read_file_to_bytes(input) catch {
    _ => abort("cannot read " + input)
  }
  let view = raw.exact_view()
  if view.length() < 4 {
    abort("dataset is shorter than its header")
  }
  let rows = view.unsafe_read_uint32_le(0).reinterpret_as_int()
  let expected = 4 + rows * 8 + rows * 4
  if view.length() != expected {
    abort(
      "dataset size " +
      view.length().to_string() +
      " does not match " +
      rows.to_string() +
      " rows",
    )
  }

  // Materialize the two columns once, before the timed loop.
  let values_start = 4
  let indices_start = values_start + rows * 8
  let values : Array[UInt64] = Array::make(rows, 0UL)
  let indices : Array[Int32] = Array::make(rows, 0)
  let mut row = 0
  while row < rows {
    values[row] = view.unsafe_read_uint64_le(values_start + row * 8)
    indices[row] = view
      .unsafe_read_uint32_le(indices_start + row * 4)
      .reinterpret_as_int()
    row = row + 1
  }

  let out : Array[UInt64] = Array::make(rows, 0UL)
  let bench = @bench.Bench()
  let mut checksum = 0UL
  let mut iteration = 0
  while iteration < repeat {
    let last = gather(values, indices, out)
    checksum = last
    bench.keep(checksum)
    iteration = iteration + 1
  }

  let json = "{\n  \"rows\": " +
    rows.to_string() +
    ",\n  \"checksum\": \"" +
    hex16(checksum) +
    "\"\n}\n"
  @fs.write_string_to_file(output, json) catch {
    _ => abort("cannot write " + output)
  }
}
