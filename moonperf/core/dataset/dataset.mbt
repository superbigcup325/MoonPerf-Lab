///|
/// Dataset generation: the generator registry and the byte layouts the protocol
/// defines. A generator id is a promise that its bytes never change; a new
/// algorithm gets a new id. Adding a generator means adding a branch to
/// `validate` and to `generate`, and a workload manifest that selects it.

///|
pub suberror DatasetError {
  Message(String)
}

///|
fn[T] fail(message : String) -> T raise DatasetError {
  raise DatasetError::Message(message)
}

///|
/// One dataset parameter, as written under `[dataset.params]` in a manifest.
pub(all) enum ParamValue {
  Int(Int64)
  Float(Double)
  Text(String)
}

///|
/// The SplitMix64 stream. Every generator draws from it, so the byte layouts
/// share one definition of the state advance and the mix.
priv struct SplitMix64 {
  mut state : UInt64
}

///|
fn SplitMix64::new(seed : Int64) -> SplitMix64 {
  { state: seed.reinterpret_as_uint64(), }
}

///|
/// One draw: advance the state by the golden gamma, then mix it. The mix is the
/// same three-step function for every generator.
fn SplitMix64::next(self : SplitMix64) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// Append one little-endian `u32`. `value` is an `Int` below 2^32.
fn push_u32_le(out : Array[Byte], value : Int32) -> Unit {
  out.push((value & 0xFF).to_byte())
  out.push(((value >> 8) & 0xFF).to_byte())
  out.push(((value >> 16) & 0xFF).to_byte())
  out.push(((value >> 24) & 0xFF).to_byte())
}

///|
/// The uniform-f64 generator, exactly as specified by the experiment protocol.
///
/// SplitMix64 advances one state per element; the top 53 bits become a uniform
/// double in [0, 1), and the value is mapped to [min, max). The output is raw
/// little-endian f64 bytes with no header.
pub fn uniform_f64_bytes(
  count : Int32,
  seed : Int64,
  min_value : Double,
  max_value : Double,
) -> Bytes {
  guard! count > 0
  guard! seed >= 0L
  guard! min_value < max_value
  let out : FixedArray[Byte] = FixedArray::make(count * 8, b'\x00')
  let span = max_value - min_value
  let scale = 1.0 / 9007199254740992.0 // 2^-53
  let rng = SplitMix64::new(seed)
  for index in 0..<count {
    let z = rng.next()
    let unit = (z >> 11).to_double() * scale
    let value = min_value + span * unit
    let bytes = value.reinterpret_as_uint64().to_le_bytes()
    for offset in 0..<8 {
      out[index * 8 + offset] = bytes.unsafe_get(offset)
    }
  }
  Bytes::from_array(out)
}

///|
/// The structured-records generator: a flat stream of fixed 16-byte records,
/// each a little-endian `u64` key followed by a little-endian `u64` payload.
/// Keys are uniform in `[0, 2^key_bits)` and payloads are uniform in
/// `[payload_min, payload_max]`. The state advances twice per record, so key
/// and payload are independent draws from the same stream.
pub fn structured_records_bytes(
  count : Int32,
  seed : Int64,
  key_bits : Int64,
  payload_min : Int64,
  payload_max : Int64,
) -> Bytes {
  guard! count > 0
  guard! seed >= 0L
  guard! key_bits >= 1L && key_bits <= 64L
  guard! payload_min >= 0L
  guard! payload_max >= payload_min
  let span = (payload_max - payload_min).reinterpret_as_uint64() + 1UL
  let shift = (64L - key_bits).to_int()
  let out : FixedArray[Byte] = FixedArray::make(count * 16, b'\x00')
  let rng = SplitMix64::new(seed)
  for index in 0..<count {
    let key_z = rng.next()
    let payload_z = rng.next()
    let key = if key_bits == 64L { key_z } else { key_z >> shift }
    let payload = payload_min.reinterpret_as_uint64() + payload_z % span
    let key_bytes = key.to_le_bytes()
    for offset in 0..<8 {
      out[index * 16 + offset] = key_bytes.unsafe_get(offset)
    }
    let payload_bytes = payload.to_le_bytes()
    for offset in 0..<8 {
      out[index * 16 + 8 + offset] = payload_bytes.unsafe_get(offset)
    }
  }
  Bytes::from_array(out)
}

///|
/// The strings generator: a dictionary-encoded string column.
///
/// Layout, little-endian, no padding: `u32 dictionary_size`, then for each
/// entry a `u32` byte length and that many ASCII bytes in `a..z`, then `count`
/// `u32` indices into the dictionary.
///
/// Each dictionary entry draws its length, then one draw per byte. Each row
/// draws `skew` values and keeps the smallest, then scales it to the
/// dictionary: `index = ((z >> 32) * distinct) >> 32`. A larger `skew` puts
/// more rows on the low indices, which is the skewed distribution the join and
/// gather workloads need; `skew = 1` is uniform.
pub fn strings_bytes(
  count : Int32,
  seed : Int64,
  distinct : Int32,
  value_len_min : Int32,
  value_len_max : Int32,
  skew : Int32,
) -> Bytes {
  guard! count > 0
  guard! seed >= 0L
  guard! distinct >= 1
  guard! value_len_min >= 1
  guard! value_len_max >= value_len_min
  guard! value_len_max <= 255
  guard! skew >= 1
  let rng = SplitMix64::new(seed)
  let span = (value_len_max - value_len_min + 1).to_uint64()
  let out : Array[Byte] = []
  push_u32_le(out, distinct)
  for _ in 0..<distinct {
    let length = value_len_min + (rng.next() % span).to_int()
    push_u32_le(out, length)
    for _ in 0..<length {
      out.push(b'a' + (rng.next() % 26).to_int().to_byte())
    }
  }
  let catalogue = distinct.to_int64().reinterpret_as_uint64()
  for _ in 0..<count {
    let mut z = rng.next()
    let mut draw = 1
    while draw < skew {
      let candidate = rng.next()
      if candidate < z {
        z = candidate
      }
      draw = draw + 1
    }
    let index = ((z >> 32) * catalogue) >> 32
    push_u32_le(out, index.to_int())
  }
  Bytes::from_array(out)
}

///|
fn required(
  params : Map[String, ParamValue],
  key : String,
  generator : String,
) -> ParamValue raise DatasetError {
  match params.get(key) {
    Some(value) => value
    None => fail("dataset.params." + key + " is required by " + generator)
  }
}

///|
fn int_param(
  params : Map[String, ParamValue],
  key : String,
  generator : String,
) -> Int64 raise DatasetError {
  match required(params, key, generator) {
    Int(value) => value
    _ => fail("dataset.params." + key + " must be an integer for " + generator)
  }
}

///|
fn float_param(
  params : Map[String, ParamValue],
  key : String,
  generator : String,
) -> Double raise DatasetError {
  match required(params, key, generator) {
    Float(value) => value
    _ => fail("dataset.params." + key + " must be a number for " + generator)
  }
}

///|
/// Check that a generator id exists and that its parameters are well formed.
/// Called while parsing the manifest, so a bad generator is a validation error
/// instead of a failure halfway through a run.
pub fn validate(
  generator : String,
  params : Map[String, ParamValue],
) -> Unit raise DatasetError {
  match generator {
    "uniform-f64" => {
      let min_value = float_param(params, "min", generator)
      let max_value = float_param(params, "max", generator)
      guard min_value < max_value else {
        fail("dataset.params.min must be below dataset.params.max")
      }
    }
    "structured-records" => {
      let key_bits = int_param(params, "key_bits", generator)
      guard key_bits >= 1L && key_bits <= 64L else {
        fail("dataset.params.key_bits must be between 1 and 64")
      }
      let payload_min = int_param(params, "payload_min", generator)
      let payload_max = int_param(params, "payload_max", generator)
      guard payload_min >= 0L else {
        fail("dataset.params.payload_min must be non-negative")
      }
      guard payload_max >= payload_min else {
        fail("dataset.params.payload_max must be at least payload_min")
      }
    }
    "strings" => {
      let distinct = int_param(params, "distinct", generator)
      guard distinct >= 1L && distinct <= 1_000_000L else {
        fail("dataset.params.distinct must be between 1 and 1000000")
      }
      let value_len_min = int_param(params, "value_len_min", generator)
      let value_len_max = int_param(params, "value_len_max", generator)
      guard value_len_min >= 1L else {
        fail("dataset.params.value_len_min must be at least 1")
      }
      guard value_len_max >= value_len_min && value_len_max <= 255L else {
        fail(
          "dataset.params.value_len_max must be between value_len_min and 255",
        )
      }
      let skew = int_param(params, "skew", generator)
      guard skew >= 1L && skew <= 8L else {
        fail("dataset.params.skew must be between 1 and 8")
      }
    }
    other => fail("dataset.generator is not implemented by the core: " + other)
  }
}

///|
/// The registry dispatch: validate, then produce the bytes for one generator.
pub fn generate(
  generator : String,
  count : Int32,
  seed : Int64,
  params : Map[String, ParamValue],
) -> Bytes raise DatasetError {
  validate(generator, params)
  match generator {
    "uniform-f64" =>
      uniform_f64_bytes(
        count,
        seed,
        float_param(params, "min", generator),
        float_param(params, "max", generator),
      )
    "structured-records" =>
      structured_records_bytes(
        count,
        seed,
        int_param(params, "key_bits", generator),
        int_param(params, "payload_min", generator),
        int_param(params, "payload_max", generator),
      )
    "strings" =>
      strings_bytes(
        count,
        seed,
        int_param(params, "distinct", generator).to_int(),
        int_param(params, "value_len_min", generator).to_int(),
        int_param(params, "value_len_max", generator).to_int(),
        int_param(params, "skew", generator).to_int(),
      )
    // `validate` already rejected every other id.
    other => fail("dataset.generator is not implemented by the core: " + other)
  }
}

///|
/// Read an integer parameter without raising. Consumers that want a value
/// rather than a validation error (tests, reporting) use this.
pub fn param_int(params : Map[String, ParamValue], key : String) -> Int64? {
  match params.get(key) {
    Some(Int(value)) => Some(value)
    _ => None
  }
}

///|
pub fn param_float(params : Map[String, ParamValue], key : String) -> Double? {
  match params.get(key) {
    Some(Float(value)) => Some(value)
    _ => None
  }
}

///|
/// A short, stable digest of the parameter set. It names the cache file, so two
/// datasets with the same generator, count and seed but different parameters
/// cannot collide, and floats are digested by bit pattern rather than by a
/// locale-dependent printing.
pub fn params_digest(params : Map[String, ParamValue]) -> String {
  let keys : Array[String] = []
  for key, _ in params {
    keys.push(key)
  }
  keys.sort()
  let mut canonical = ""
  for key in keys {
    let text = match params.get(key) {
      Some(Int(number)) => "i" + number.to_string()
      Some(Float(number)) => "f" + number.reinterpret_as_uint64().to_string()
      Some(Text(text)) => "s" + text
      None => "s"
    }
    canonical = canonical + key + "=" + text + ";"
  }
  let digest = sha256_hex(@utf8.encode(canonical))
  digest[:8].to_owned()
}

///|
pub fn sha256_hex(data : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(data))
}
