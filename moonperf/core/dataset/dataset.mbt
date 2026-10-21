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
/// The SplitMix64 output function. `uniform-f64` and `structured-records` share
/// it so that one implementation of the mix is enough for both layouts.
fn mix64(state : UInt64) -> UInt64 {
  let mut z = state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
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
  let mut state : UInt64 = seed.reinterpret_as_uint64()
  for index in 0..<count {
    state = state + 0x9E3779B97F4A7C15UL
    let z = mix64(state)
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
  let mut state : UInt64 = seed.reinterpret_as_uint64()
  for index in 0..<count {
    state = state + 0x9E3779B97F4A7C15UL
    let key_z = mix64(state)
    state = state + 0x9E3779B97F4A7C15UL
    let payload_z = mix64(state)
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
