///|
/// Summary statistics for one implementation's raw per-iteration samples.
pub struct Summary {
  count : Int32
  min_ns : Int64
  median_ns : Double
  mean_ns : Double
  stdev_ns : Double
  cv : Double
}

///|
pub fn make_summary(
  count : Int32,
  min_ns : Int64,
  median_ns : Double,
  mean_ns : Double,
  stdev_ns : Double,
  cv : Double,
) -> Summary {
  { count, min_ns, median_ns, mean_ns, stdev_ns, cv, }
}

///|
pub fn summarize(samples : Array[Int64]) -> Summary? {
  let count = samples.length()
  if count == 0 {
    return None
  }
  let sorted = samples.copy()
  sorted.sort()
  let min_ns = sorted[0]
  let median_ns = if count % 2 == 1 {
    sorted[count / 2].to_double()
  } else {
    (sorted[count / 2 - 1].to_double() + sorted[count / 2].to_double()) / 2.0
  }
  let mut total = 0.0
  for sample in samples {
    total = total + sample.to_double()
  }
  let mean_ns = total / count.to_double()
  let mut squared = 0.0
  if count > 1 {
    for sample in samples {
      let delta = sample.to_double() - mean_ns
      squared = squared + delta * delta
    }
  }
  let stdev_ns = if count > 1 {
    (squared / (count - 1).to_double()).sqrt()
  } else {
    0.0
  }
  let cv = if mean_ns == 0.0 { 0.0 } else { stdev_ns / mean_ns }
  Some({ count, min_ns, median_ns, mean_ns, stdev_ns, cv, })
}
