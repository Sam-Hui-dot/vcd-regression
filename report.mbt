///|
pub struct Difference {
  cycle : Int32
  signal : String
  expected : String
  actual : String
  baseline_fs : Int64
  candidate_fs : Int64
}

///|
pub struct SignalSummary {
  signal : String
  differing_cycles : Int32
  first_cycle : Int32?
  last_cycle : Int32?
}

///|
pub struct RegressionReport {
  status : String
  start_cycle : Int32
  compared_cycles : Int32
  baseline_cycles : Int32
  candidate_cycles : Int32
  differing_cycles : Int32
  difference_count : Int64
  truncated : Bool
  differences : Array[Difference]
  signals : Array[SignalSummary]
}

///|
fn selected_length(length : Int32, skip : Int32, limit : Int32?) -> Int32 {
  let remaining = length - skip
  match limit {
    Some(count) => if remaining < count { remaining } else { count }
    None => remaining
  }
}

///|
/// Compare a cycle window and retain a bounded list of differences.
/// Statistics always cover the full selected window, even after the list fills.
pub fn regression_report(
  baseline : Trace,
  candidate : Trace,
  skip_cycles~ : Int32 = 0,
  cycles? : Int32,
  max_differences~ : Int32 = 100,
) -> RegressionReport raise TraceError {
  if baseline.signals != candidate.signals {
    raise InvalidTrace("traces select different signals")
  }
  if baseline.widths != candidate.widths {
    raise InvalidTrace("selected signal widths differ between traces")
  }
  if skip_cycles < 0 {
    raise InvalidTrace("skip_cycles must be nonnegative")
  }
  if cycles is Some(count) && count <= 0 {
    raise InvalidTrace("cycles must be positive")
  }
  if max_differences <= 0 {
    raise InvalidTrace("max_differences must be positive")
  }
  if skip_cycles >= baseline.samples.length() ||
    skip_cycles >= candidate.samples.length() {
    raise InvalidTrace("cycle window starts beyond available samples")
  }
  let left_count = selected_length(
    baseline.samples.length(),
    skip_cycles,
    cycles,
  )
  let right_count = selected_length(
    candidate.samples.length(),
    skip_cycles,
    cycles,
  )
  let count = if left_count < right_count { left_count } else { right_count }
  let differences : Array[Difference] = []
  let counts = Array::make(baseline.signals.length(), 0)
  let first : Array[Int32?] = Array::make(baseline.signals.length(), None)
  let last : Array[Int32?] = Array::make(baseline.signals.length(), None)
  let mut difference_count = 0L
  let mut differing_cycles = 0
  for offset in 0..<count {
    let index = skip_cycles + offset
    let expected = baseline.samples[index]
    let actual = candidate.samples[index]
    let mut changed = false
    for signal_index, signal in baseline.signals {
      if expected.values[signal_index] != actual.values[signal_index] {
        changed = true
        difference_count += 1L
        counts[signal_index] += 1
        if first[signal_index] is None {
          first[signal_index] = Some(index + 1)
        }
        last[signal_index] = Some(index + 1)
        if differences.length() < max_differences {
          differences.push({
            cycle: index + 1,
            signal,
            expected: expected.values[signal_index],
            actual: actual.values[signal_index],
            baseline_fs: expected.time_fs,
            candidate_fs: actual.time_fs,
          })
        }
      }
    }
    if changed {
      differing_cycles += 1
    }
  }
  let summaries : Array[SignalSummary] = []
  for index, signal in baseline.signals {
    summaries.push({
      signal,
      differing_cycles: counts[index],
      first_cycle: first[index],
      last_cycle: last[index],
    })
  }
  let status = if difference_count > 0L {
    "different"
  } else if left_count != right_count {
    "length_mismatch"
  } else {
    "match"
  }
  {
    status,
    start_cycle: skip_cycles + 1,
    compared_cycles: count,
    baseline_cycles: left_count,
    candidate_cycles: right_count,
    differing_cycles,
    difference_count,
    truncated: difference_count > differences.length().to_int64(),
    differences,
    signals: summaries,
  }
}

///|
fn optional_cycle_json(cycle : Int32?) -> Json {
  match cycle {
    Some(value) => @json.to_json(value)
    None => Json::null()
  }
}

///|
fn Difference::json(self : Difference) -> Json {
  Json::object(
    Map([
      ("cycle", @json.to_json(self.cycle)),
      ("signal", @json.to_json(self.signal)),
      ("expected", @json.to_json(self.expected)),
      ("actual", @json.to_json(self.actual)),
      ("baseline_fs", @json.to_json(self.baseline_fs.to_string())),
      ("candidate_fs", @json.to_json(self.candidate_fs.to_string())),
    ]),
  )
}

///|
fn SignalSummary::json(self : SignalSummary) -> Json {
  Json::object(
    Map([
      ("signal", @json.to_json(self.signal)),
      ("differing_cycles", @json.to_json(self.differing_cycles)),
      ("first_cycle", optional_cycle_json(self.first_cycle)),
      ("last_cycle", optional_cycle_json(self.last_cycle)),
    ]),
  )
}

///|
/// Decimal timestamps and aggregate difference counts are strings, preserving Int64.
pub fn RegressionReport::to_json(self : RegressionReport) -> String {
  Json::object(
    Map([
      ("status", @json.to_json(self.status)),
      ("start_cycle", @json.to_json(self.start_cycle)),
      ("compared_cycles", @json.to_json(self.compared_cycles)),
      ("baseline_cycles", @json.to_json(self.baseline_cycles)),
      ("candidate_cycles", @json.to_json(self.candidate_cycles)),
      ("differing_cycles", @json.to_json(self.differing_cycles)),
      ("difference_count", @json.to_json(self.difference_count.to_string())),
      ("truncated", @json.to_json(self.truncated)),
      ("differences", Json::array(self.differences.map(item => item.json()))),
      ("signals", Json::array(self.signals.map(item => item.json()))),
    ]),
  ).stringify()
}

///|
/// Render the original first-difference JSON schema without a JavaScript FFI.
pub fn comparison_json(result : Comparison) -> String {
  let (status, cycles, signal, expected, actual, base_fs, run_fs) = match
    result {
    Match(count) => ("match", count, "", "", "", "", "")
    Different(cycle, name, expected, actual, base, run) =>
      (
        "different",
        cycle,
        name,
        expected,
        actual,
        base.to_string(),
        run.to_string(),
      )
    LengthMismatch(expected, actual) =>
      (
        "length_mismatch",
        0,
        "",
        expected.to_string(),
        actual.to_string(),
        "",
        "",
      )
  }
  Json::object(
    Map([
      ("status", @json.to_json(status)),
      ("cycles", @json.to_json(cycles)),
      ("signal", @json.to_json(signal)),
      ("expected", @json.to_json(expected)),
      ("actual", @json.to_json(actual)),
      ("baseline_fs", @json.to_json(base_fs)),
      ("candidate_fs", @json.to_json(run_fs)),
      ("message", @json.to_json("")),
    ]),
  ).stringify()
}

///|
pub fn invalid_json(message : String) -> String {
  Json::object(
    Map([
      ("status", @json.to_json("invalid")),
      ("cycles", @json.to_json(0)),
      ("signal", @json.to_json("")),
      ("expected", @json.to_json("")),
      ("actual", @json.to_json("")),
      ("baseline_fs", @json.to_json("")),
      ("candidate_fs", @json.to_json("")),
      ("message", @json.to_json(message)),
    ]),
  ).stringify()
}

///|
pub fn RegressionReport::to_text(self : RegressionReport) -> String {
  let lines = [
    "REPORT \{self.status}: \{self.compared_cycles} compared cycles from cycle \{self.start_cycle}",
    "samples: baseline \{self.baseline_cycles}, candidate \{self.candidate_cycles}",
    "differences: \{self.difference_count} values across \{self.differing_cycles} cycles",
  ]
  for difference in self.differences {
    lines.push(
      "cycle \{difference.cycle}, \{difference.signal}: expected \{difference.expected} at \{difference.baseline_fs} fs, got \{difference.actual} at \{difference.candidate_fs} fs",
    )
  }
  if self.truncated {
    lines.push(
      "difference list truncated; statistics cover the full selected window",
    )
  }
  for signal in self.signals {
    if signal.differing_cycles > 0 {
      lines.push(
        "signal \{signal.signal}: \{signal.differing_cycles} differing cycles",
      )
    }
  }
  lines.join("\n")
}
