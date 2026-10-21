//! hash-join: the MoonBit implementation.
//!
//! The dataset is one `structured-records` stream (16-byte records: a `u64` key
//! and a `u64` payload). The first half is the build side, the second half is
//! the probe side. The kernel builds a chained hash table over the build side,
//! probes it with every probe row, and counts the matching (build, probe) pairs
//! plus a wrapping checksum of their payloads.

///|
const GAMMA : UInt64 = 0x9E3779B97F4A7C15UL

///|
const EMPTY : Int = -1

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
/// The table index: the top 32 bits of the multiply-shift product, masked to
/// the table size. The mask form keeps every implementation on the same table
/// shape.
fn slot_of(key : UInt64, mask : Int) -> Int {
  ((key * GAMMA) >> 32).to_int() & mask
}

///|
/// One join pass: build the table, probe it, return (pairs, checksum).
fn join(data : Array[UInt64], rows : Int, build_rows : Int) -> (UInt64, UInt64) {
  let mut table_size = 16
  while table_size < build_rows * 2 {
    table_size = table_size * 2
  }
  let mask = table_size - 1
  let heads : Array[Int] = Array::make(table_size, EMPTY)
  let next : Array[Int] = Array::make(build_rows, EMPTY)
  let mut row = 0
  while row < build_rows {
    let slot = slot_of(data[row * 2], mask)
    next[row] = heads[slot]
    heads[slot] = row
    row = row + 1
  }
  let mut pairs = 0UL
  let mut checksum = 0UL
  let mut probe = build_rows
  while probe < rows {
    let key = data[probe * 2]
    let payload = data[probe * 2 + 1]
    let slot = slot_of(key, mask)
    let mut cursor = heads[slot]
    while cursor != EMPTY {
      if data[cursor * 2] == key {
        pairs = pairs + 1UL
        checksum = checksum + data[cursor * 2 + 1] + payload
      }
      cursor = next[cursor]
    }
    probe = probe + 1
  }
  (pairs, checksum)
}

///|
/// A `u64` as 16 lowercase hex digits, so the JSON value is exact.
fn hex16(value : UInt64) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut index = 0
  while index < 16 {
    let shift : Int = (15 - index) * 4
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
  if view.length() % 16 != 0 {
    abort("dataset size must be a multiple of 16 bytes")
  }
  let rows = view.length() / 16
  if rows == 0 || rows % 2 != 0 {
    abort("the dataset must contain a positive even number of records")
  }
  let build_rows = rows / 2

  // Materialize the records once, before the timed loop.
  let data : Array[UInt64] = Array::make(rows * 2, 0UL)
  let mut index = 0
  while index < rows * 2 {
    data[index] = view.unsafe_read_uint64_le(index * 8)
    index = index + 1
  }

  let bench = @bench.Bench()
  let mut pairs = 0UL
  let mut checksum = 0UL
  let mut iteration = 0
  while iteration < repeat {
    let (last_pairs, last_checksum) = join(data, rows, build_rows)
    pairs = last_pairs
    checksum = last_checksum
    bench.keep(pairs)
    iteration = iteration + 1
  }

  let json = "{\n" +
    "  \"build_rows\": " +
    build_rows.to_string() +
    ",\n  \"probe_rows\": " +
    (rows - build_rows).to_string() +
    ",\n  \"pairs\": " +
    pairs.to_string() +
    ",\n  \"checksum\": \"" +
    hex16(checksum) +
    "\"\n}\n"
  @fs.write_string_to_file(output, json) catch {
    _ => abort("cannot write " + output)
  }
}
