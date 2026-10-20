///|
test "summary of odd samples" {
  let summary = @measure.summarize([3L, 1L, 2L]).unwrap()
  inspect(summary.count, content="3")
  inspect(summary.min_ns, content="1")
  inspect(summary.median_ns, content="2")
  inspect(summary.mean_ns, content="2")
  inspect(summary.stdev_ns, content="1")
  inspect(summary.cv, content="0.5")
}

///|
test "summary of even samples" {
  let summary = @measure.summarize([1L, 2L, 3L, 4L]).unwrap()
  inspect(summary.median_ns, content="2.5")
  inspect(summary.mean_ns, content="2.5")
}

///|
test "single sample has zero deviation" {
  let summary = @measure.summarize([7L]).unwrap()
  inspect(summary.stdev_ns, content="0")
  inspect(summary.cv, content="0")
}

///|
test "empty samples have no summary" {
  inspect(@measure.summarize([]) is None, content="true")
}
