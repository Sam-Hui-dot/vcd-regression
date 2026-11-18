///|
pub struct TracePair {
  baseline : Trace
  candidate : Trace
  priv baseline_inputs : Trace?
  priv candidate_inputs : Trace?
}

///|
pub(all) enum StimulusCheck {
  StimulusMatch(Int32)
  StimulusDifference(Difference)
  StimulusLengthMismatch(Int32, Int32)
  StimulusUnknown(Int32, String, String, String)
}

///|
fn projected_trace(
  trace : Trace,
  names : Array[String],
  positions : Array[Int32],
) -> Trace {
  {
    signals: names,
    widths: positions.map(index => trace.widths[index]),
    samples: trace.samples.map(sample => {
      time_fs: sample.time_fs,
      values: positions.map(index => sample.values[index]),
    }),
  }
}

///|
fn capture_side(
  text : String,
  clock : String,
  reset : String,
  output_paths : Array[String],
  input_paths : Array[String],
  output_names : Array[String],
  input_names : Array[String],
) -> (Trace, Trace?) raise TraceError {
  let positions : Map[String, Int32] = Map([])
  for index, path in output_paths {
    if positions.contains(path) {
      raise InvalidTrace("duplicate output mapping: \{path}")
    }
    positions[path] = index
  }
  let paths = output_paths.copy()
  let input_positions : Array[Int32] = []
  let seen_inputs : Map[String, Bool] = Map([])
  for path in input_paths {
    if seen_inputs.contains(path) {
      raise InvalidTrace("duplicate input mapping: \{path}")
    }
    seen_inputs[path] = true
    match positions.get(path) {
      Some(index) => input_positions.push(index)
      None => {
        input_positions.push(paths.length())
        paths.push(path)
      }
    }
  }
  let captured = capture(text, clock, reset, paths)
  let output = if paths.length() == output_paths.length() {
    {
      signals: output_names,
      widths: captured.widths,
      samples: captured.samples,
    }
  } else {
    projected_trace(
      captured,
      output_names,
      Array::makei(output_paths.length(), index => index),
    )
  }
  let inputs = if input_paths.is_empty() {
    None
  } else {
    Some(projected_trace(captured, input_names, input_positions))
  }
  (output, inputs)
}

///|
/// Each pair lists the baseline path first and the candidate path second.
/// Comparison results use baseline paths as stable report labels.
pub fn capture_pair(
  baseline_text : String,
  candidate_text : String,
  clock : (String, String),
  reset : (String, String),
  outputs : Array[(String, String)],
  inputs~ : Array[(String, String)] = [],
) -> TracePair raise TraceError {
  if outputs.is_empty() {
    raise InvalidTrace("select at least one output signal")
  }
  let output_names = outputs.map(pair => pair.0)
  let input_names = inputs.map(pair => pair.0)
  let (baseline, baseline_inputs) = capture_side(
    baseline_text,
    clock.0,
    reset.0,
    output_names,
    input_names,
    output_names,
    input_names,
  )
  let (candidate, candidate_inputs) = capture_side(
    candidate_text,
    clock.1,
    reset.1,
    outputs.map(pair => pair.1),
    inputs.map(pair => pair.1),
    output_names,
    input_names,
  )
  { baseline, candidate, baseline_inputs, candidate_inputs, }
}

///|
/// Validate the known input values at every sampled cycle before comparing outputs.
pub fn TracePair::check_stimulus(
  self : TracePair,
) -> StimulusCheck? raise TraceError {
  guard self.baseline_inputs is Some(baseline) &&
    self.candidate_inputs is Some(candidate) else {
    return None
  }
  if baseline.widths != candidate.widths {
    raise InvalidTrace("mapped input signal widths differ between traces")
  }
  let count = if baseline.samples.length() < candidate.samples.length() {
    baseline.samples.length()
  } else {
    candidate.samples.length()
  }
  for index in 0..<count {
    let expected = baseline.samples[index]
    let actual = candidate.samples[index]
    for signal_index, signal in baseline.signals {
      let left = expected.values[signal_index]
      let right = actual.values[signal_index]
      if left.contains("x") ||
        left.contains("z") ||
        right.contains("x") ||
        right.contains("z") {
        return Some(StimulusUnknown(index + 1, signal, left, right))
      }
      if left != right {
        return Some(
          StimulusDifference({
            cycle: index + 1,
            signal,
            expected: left,
            actual: right,
            baseline_fs: expected.time_fs,
            candidate_fs: actual.time_fs,
          }),
        )
      }
    }
  }
  if baseline.samples.length() != candidate.samples.length() {
    Some(
      StimulusLengthMismatch(
        baseline.samples.length(),
        candidate.samples.length(),
      ),
    )
  } else {
    Some(StimulusMatch(count))
  }
}

///|
pub fn StimulusCheck::to_json(self : StimulusCheck) -> String {
  let fields = match self {
    StimulusMatch(count) =>
      [
        ("status", @json.to_json("stimulus_match")),
        ("cycles", @json.to_json(count)),
      ]
    StimulusDifference(item) =>
      [
        ("status", @json.to_json("stimulus_mismatch")),
        ("difference", item.json()),
      ]
    StimulusLengthMismatch(left, right) =>
      [
        ("status", @json.to_json("stimulus_length_mismatch")),
        ("baseline_cycles", @json.to_json(left)),
        ("candidate_cycles", @json.to_json(right)),
      ]
    StimulusUnknown(cycle, signal, left, right) =>
      [
        ("status", @json.to_json("stimulus_unknown")),
        ("cycle", @json.to_json(cycle)),
        ("signal", @json.to_json(signal)),
        ("expected", @json.to_json(left)),
        ("actual", @json.to_json(right)),
      ]
  }
  Json::object(Map(fields)).stringify()
}

///|
pub fn StimulusCheck::to_text(self : StimulusCheck) -> String {
  match self {
    StimulusMatch(count) => "STIMULUS MATCH: \{count} sampled cycles"
    StimulusDifference(item) =>
      "STIMULUS MISMATCH cycle \{item.cycle}, \{item.signal}: baseline \{item.expected}, candidate \{item.actual}"
    StimulusLengthMismatch(left, right) =>
      "STIMULUS LENGTH MISMATCH: baseline \{left} cycles, candidate \{right} cycles"
    StimulusUnknown(cycle, signal, left, right) =>
      "STIMULUS UNKNOWN cycle \{cycle}, \{signal}: baseline \{left}, candidate \{right}"
  }
}
