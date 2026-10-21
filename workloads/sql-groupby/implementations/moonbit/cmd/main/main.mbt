//! sql-groupby: the MoonBit implementation, hand-written.
//!
//! The dataset is a `csv-records` file: `id,category,amount` and one row per
//! record. This implementation parses the CSV itself and answers the fixed
//! query without a SQL engine, so it is the like-for-like counterpart of the
//! Rust and C implementations:
//!
//!   SELECT category, count(*) AS n, sum(amount) AS total
//!   FROM t GROUP BY category ORDER BY category
//!
//! and folds the result into a checksum: for output row `i`, add
//! `n * (i + 1) + total` to a wrapping 64-bit accumulator.

///|
const CATEGORIES : Int32 = 4096

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
/// Parse one decimal integer, stopping at a delimiter.
fn parse_number(
  bytes : BytesView,
  length : Int32,
  cursor : Ref[Int32],
) -> UInt64 {
  let mut value = 0UL
  let mut digits = 0
  while cursor.val < length {
    let byte = bytes.unsafe_get(cursor.val)
    if byte < b'0' || byte > b'9' {
      break
    }
    value = value * 10UL + (byte - b'0').to_uint64()
    digits = digits + 1
    cursor.val = cursor.val + 1
  }
  if digits == 0 {
    abort("csv: expected a decimal integer")
  }
  value
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
  let bytes = raw.exact_view()
  let length = bytes.length()

  let counts : Array[UInt64] = Array::make(CATEGORIES, 0UL)
  let totals : Array[UInt64] = Array::make(CATEGORIES, 0UL)
  let bench = @bench.Bench()
  let mut groups = 0UL
  let mut rows = 0UL
  let mut checksum = 0UL
  let mut iteration = 0
  while iteration < repeat {
    for slot in 0..<CATEGORIES {
      counts[slot] = 0UL
      totals[slot] = 0UL
    }
    let cursor = Ref(0)
    // Header: skip to the first newline.
    while cursor.val < length && bytes.unsafe_get(cursor.val) != b'\n' {
      cursor.val = cursor.val + 1
    }
    if cursor.val < length {
      cursor.val = cursor.val + 1
    }
    let mut row_count = 0UL
    while cursor.val < length {
      let _id = parse_number(bytes, length, cursor)
      if cursor.val >= length || bytes.unsafe_get(cursor.val) != b',' {
        abort("csv: expected ',' after id")
      }
      cursor.val = cursor.val + 1
      let category = parse_number(bytes, length, cursor)
      if cursor.val >= length || bytes.unsafe_get(cursor.val) != b',' {
        abort("csv: expected ',' after category")
      }
      cursor.val = cursor.val + 1
      let amount = parse_number(bytes, length, cursor)
      if cursor.val < length && bytes.unsafe_get(cursor.val) == b'\r' {
        cursor.val = cursor.val + 1
      }
      if cursor.val < length && bytes.unsafe_get(cursor.val) == b'\n' {
        cursor.val = cursor.val + 1
      }
      let slot = category.to_int()
      if slot >= CATEGORIES {
        abort("csv: category out of the declared range")
      }
      counts[slot] = counts[slot] + 1UL
      totals[slot] = totals[slot] + amount
      row_count = row_count + 1UL
    }
    let mut group_count = 0UL
    let mut sum = 0UL
    for slot in 0..<CATEGORIES {
      if counts[slot] == 0UL {
        continue
      }
      group_count = group_count + 1UL
      sum = sum + counts[slot] * group_count + totals[slot]
    }
    rows = row_count
    groups = group_count
    checksum = sum
    bench.keep(checksum)
    iteration = iteration + 1
  }

  let json = "{\n  \"groups\": " +
    groups.to_string() +
    ",\n  \"rows\": " +
    rows.to_string() +
    ",\n  \"checksum\": \"" +
    hex16(checksum) +
    "\"\n}\n"
  @fs.write_string_to_file(output, json) catch {
    _ => abort("cannot write " + output)
  }
}
