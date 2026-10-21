//! sql-groupby: the Moonlake implementation.
//!
//! The dataset is a `csv-records` file registered as a table through
//! moonlake's public API (a CSV scan source, a catalog, `execute`). The query
//! is the same fixed one the hand-written implementations answer:
//!
//!   SELECT category, count(*) AS n, sum(amount) AS total
//!   FROM t GROUP BY category ORDER BY category
//!
//! This adapter measures the engine's end-to-end path — register, parse, plan,
//! scan, aggregate — not a hand-written loop. The workload README is explicit
//! that the comparison is engine versus hand-written pipeline.

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
/// Read an integer cell as a wrapping `u64`, whatever numeric width the engine
/// chose for the column.
fn cell_u64(column : @types.ColumnVector, row : Int) -> UInt64 {
  match column.get(row) {
    @types.Scalar::Int32(value) => value.to_int64().reinterpret_as_uint64()
    @types.Scalar::Int64(value) => value.reinterpret_as_uint64()
    @types.Scalar::Float64(value) => value.to_int64().reinterpret_as_uint64()
    _ => abort("result column is not numeric")
  }
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

  let sql = "SELECT category, count(*) AS n, sum(amount) AS total " +
    "FROM t GROUP BY category ORDER BY category"
  let catalog = @catalog.Catalog::new()
  let entry = @csv.scan_file(input, "t") catch {
    _ => abort("moonlake: cannot register " + input)
  }
  catalog.register(entry)

  let mut groups = 0UL
  let mut rows = 0UL
  let mut checksum = 0UL
  let mut iteration = 0
  while iteration < repeat {
    let result = @moonlake.execute(sql, catalog) catch {
      _ => abort("moonlake: query failed")
    }
    let batch = result.batch()
    let columns = batch.columns()
    if columns.length() < 3 {
      abort("moonlake: expected three result columns")
    }
    let group_rows = batch.row_count()
    let mut sum = 0UL
    let mut total_rows = 0UL
    let mut index = 0
    while index < group_rows {
      let count = cell_u64(columns[1], index)
      let total = cell_u64(columns[2], index)
      total_rows = total_rows + count
      sum = sum + count * (index + 1).to_uint64() + total
      index = index + 1
    }
    rows = total_rows
    groups = group_rows.to_uint64()
    checksum = sum
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
