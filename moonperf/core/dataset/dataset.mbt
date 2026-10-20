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
    let mut z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
    z = z ^ (z >> 31)
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
pub fn sha256_hex(data : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(data))
}
