//! numeric-scan: the MoonBit implementation.
//!
//! One sequential pass over the dataset's little-endian `f64` bytes,
//! accumulating sum, sum of squares, min, max and the number of values above a
//! threshold. The adapter contract (protocol section 5) passes the dataset, the
//! params file, the output path and the inner repeat count on the command line.

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
fn read_threshold(path : String) -> Double {
  let text = @fs.read_file_to_string(path) catch {
    _ => abort("cannot read " + path)
  }
  for line in text.split("\n") {
    if line.contains("threshold=") {
      return @string.parse_double(line.exact_view(start=10)) catch {
        _ => abort("threshold must be a number")
      }
    }
  }
  abort("params: missing threshold")
}

///|
/// JSON has one number type, but the protocol asks floats to stay floats: an
/// integral double is printed as `1.0`, never `1`.
fn format_double(value : Double) -> String {
  let text = value.to_string()
  if text.contains(".") || text.contains("e") || text.contains("E") {
    text
  } else {
    text + ".0"
  }
}

///|
/// One pass over the dataset. The first element seeds min/max/sum so the
/// result does not depend on a sentinel large enough for the data.
fn scan(
  view : BytesView,
  n : Int32,
  threshold : Double
) -> (Double, Double, Double, Double, Int) {
  let first = view.unsafe_read_uint64_le(0).reinterpret_as_double()
  let mut sum = first
  let mut sumsq = first * first
  let mut minimum = first
  let mut maximum = first
  let mut count_above = if first > threshold { 1 } else { 0 }
  let mut index = 1
  while index < n {
    let value = view.unsafe_read_uint64_le(index * 8).reinterpret_as_double()
    sum = sum + value
    sumsq = sumsq + value * value
    if value < minimum {
      minimum = value
    }
    if value > maximum {
      maximum = value
    }
    if value > threshold {
      count_above = count_above + 1
    }
    index = index + 1
  }
  (sum, sumsq, minimum, maximum, count_above)
}

///|
fn main {
  let args = @env.args()
  let input = option(args, "--input")
  let params = option(args, "--params")
  let output = option(args, "--output")
  let repeat = @string.parse_int(option(args, "--repeat")) catch {
    _ => abort("--repeat must be an integer")
  }
  let threshold = read_threshold(params)

  let raw = @fs.read_file_to_bytes(input) catch {
    _ => abort("cannot read " + input)
  }
  let view = raw.exact_view()
  let n : Int32 = view.length() / 8

  let mut sum = 0.0
  let mut sumsq = 0.0
  let mut minimum = 0.0
  let mut maximum = 0.0
  let mut count_above = 0
  let mut iteration = 0
  while iteration < repeat {
    let (last_sum, last_sumsq, last_min, last_max, last_count) = scan(
      view,
      n,
      threshold,
    )
    sum = last_sum
    sumsq = last_sumsq
    minimum = last_min
    maximum = last_max
    count_above = last_count
    iteration = iteration + 1
  }

  let json = "{\n" +
    "  \"n\": " + n.to_string() + ",\n" +
    "  \"sum\": " + format_double(sum) + ",\n" +
    "  \"sumsq\": " + format_double(sumsq) + ",\n" +
    "  \"min\": " + format_double(minimum) + ",\n" +
    "  \"max\": " + format_double(maximum) + ",\n" +
    "  \"count_above\": " + count_above.to_string() + "\n" +
    "}\n"
  @fs.write_string_to_file(output, json) catch {
    _ => abort("cannot write " + output)
  }
}
