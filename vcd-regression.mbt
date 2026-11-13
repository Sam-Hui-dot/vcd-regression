///|
pub suberror TraceError {
  InvalidTrace(String)
}

///|
struct Sample {
  time_fs : Int64
  values : Array[String]
}

///|
pub struct Trace {
  priv signals : Array[String]
  priv widths : Array[Int32]
  priv samples : Array[Sample]
}

///|
#derive(Debug, Eq)
pub(all) enum Comparison {
  Match(Int32)
  Different(Int32, String, String, String, Int64, Int64)
  LengthMismatch(Int32, Int32)
}

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
pub extend Comparison with Eq::{not_equal, equal}

///|
priv struct Tokens {
  text : String
  mut offset : Int32
}

///|
fn whitespace(ch : UInt16) -> Bool {
  ch == 32 || ch == 9 || ch == 10 || ch == 13
}

///|
fn Tokens::next(self : Tokens) -> String? {
  let length = self.text.length()
  while self.offset < length && whitespace(self.text.at(self.offset)) {
    self.offset += 1
  }
  let start = self.offset
  while self.offset < length && !whitespace(self.text.at(self.offset)) {
    self.offset += 1
  }
  if start == self.offset {
    None
  } else {
    Some(self.text[start:self.offset].to_owned())
  }
}

///|
fn Tokens::directive(self : Tokens) -> Array[String] raise TraceError {
  let result = []
  while self.next() is Some(token) {
    if token == "$end" {
      return result
    }
    result.push(token)
  }
  raise InvalidTrace("unterminated directive")
}

///|
fn time_unit(token : String) -> Int64 raise TraceError {
  let mut index = 0
  while index < token.length() && token.at(index) >= 48 && token.at(index) <= 57 {
    index += 1
  }
  let multiplier = match token[:index].to_owned() {
    "1" => 1L
    "10" => 10L
    "100" => 100L
    _ => raise InvalidTrace("unsupported timescale multiplier")
  }
  let unit = match token[index:].to_owned() {
    "s" => 1_000_000_000_000_000L
    "ms" => 1_000_000_000_000L
    "us" => 1_000_000_000L
    "ns" => 1_000_000L
    "ps" => 1_000L
    "fs" => 1L
    _ => raise InvalidTrace("unsupported timescale unit")
  }
  multiplier * unit
}

///|
priv struct Signal {
  code : String
  width : Int32
}

///|
fn declarations(
  tokens : Tokens,
) -> (Int64, Map[String, Signal]) raise TraceError {
  let scope : Array[String] = []
  let signals : Map[String, Signal] = Map([])
  let mut scale = 0L
  while tokens.next() is Some(command) {
    let fields = tokens.directive()
    match (command, fields) {
      ("$scope", [_, name]) => scope.push(name)
      ("$upscope", []) =>
        if scope.pop() is None {
          raise InvalidTrace("unbalanced scope")
        }
      ("$timescale", [value]) => scale = time_unit(value)
      ("$timescale", [value, unit]) => scale = time_unit(value + unit)
      ("$var", [kind, size, code, name, ..]) =>
        if kind != "real" && kind != "realtime" && kind != "string" {
          let width = @string.parse_int(size[:]) catch {
            _ => raise InvalidTrace("invalid signal width")
          }
          if width < 1 {
            raise InvalidTrace("invalid signal width")
          }
          let path = (scope + [name]).join(".")
          if signals.contains(path) {
            raise InvalidTrace("ambiguous signal \{path}")
          }
          signals[path] = { code, width, }
        }
      ("$enddefinitions", []) => {
        if scale == 0L || !scope.is_empty() {
          raise InvalidTrace("missing timescale or unbalanced scopes")
        }
        return (scale, signals)
      }
      ("$date" | "$version" | "$comment", _) => ()
      _ =>
        raise InvalidTrace(
          "unsupported or malformed header directive \{command}",
        )
    }
  }
  raise InvalidTrace("missing enddefinitions")
}

///|
fn resolve(
  signals : Map[String, Signal],
  name : String,
) -> Signal raise TraceError {
  match signals.get(name) {
    Some(signal) => signal
    None => raise InvalidTrace("signal not found: \{name}")
  }
}

///|
fn normalize(value : String, width : Int32) -> String raise TraceError {
  let bits = value.to_lower()
  if bits.is_empty() || bits.length() > width {
    raise InvalidTrace("invalid vector width")
  }
  for bit in bits {
    if bit != '0' && bit != '1' && bit != 'x' && bit != 'z' {
      raise InvalidTrace("invalid logic value")
    }
  }
  let lead = bits.at(0)
  let pad = if lead == 120 { 'x' } else if lead == 122 { 'z' } else { '0' }
  String::make(width - bits.length(), pad) + bits
}

///|
priv struct CaptureState {
  values : Map[String, String]
  mut previous_clock : String
  mut saw_reset : Bool
  samples : Array[Sample]
}

///|
fn CaptureState::sample(
  self : CaptureState,
  time_fs : Int64,
  clock : Signal,
  reset : Signal,
  watched : Array[Signal],
) -> Unit {
  let clock_now = self.values.get(clock.code).unwrap_or("x")
  let reset_now = self.values.get(reset.code).unwrap_or("x")
  if reset_now == "0" {
    self.saw_reset = true
  }
  if self.saw_reset &&
    reset_now == "1" &&
    self.previous_clock == "0" &&
    clock_now == "1" {
    self.samples.push({
      time_fs,
      values: watched.map(signal => {
        self.values.get(signal.code).unwrap_or(String::make(signal.width, 'x'))
      }),
    })
  }
  self.previous_clock = clock_now
}

///|
/// Compare values after all changes at each rising edge, starting after
/// observed active-low reset.
pub fn capture(
  text : String,
  clock_name : String,
  reset_name : String,
  names : Array[String],
) -> Trace raise TraceError {
  let tokens : Tokens = { text, offset: 0, }
  let (scale, signals) = declarations(tokens)
  let clock = resolve(signals, clock_name)
  let reset = resolve(signals, reset_name)
  if clock.width != 1 ||
    reset.width != 1 ||
    clock.code == reset.code ||
    names.is_empty() {
    raise InvalidTrace(
      "use distinct single-bit clock and reset, and select at least one signal",
    )
  }
  let watched = []
  let widths : Map[String, Int32] = Map([(clock.code, 1), (reset.code, 1)])
  for name in names {
    let signal = resolve(signals, name)
    if widths.get(signal.code) is Some(width) && width != signal.width {
      raise InvalidTrace("conflicting width for \{name}")
    }
    widths[signal.code] = signal.width
    watched.push(signal)
  }
  let state : CaptureState = {
    values: Map([]),
    previous_clock: "x",
    saw_reset: false,
    samples: [],
  }
  let mut time = 0L
  while tokens.next() is Some(token) {
    if token.has_prefix("#") {
      let next_time = @string.parse_int64(token[1:]) catch {
        _ => raise InvalidTrace("invalid timestamp")
      }
      if next_time < time || next_time > 9_223_372_036_854_775_807L / scale {
        raise InvalidTrace("timestamp out of order or out of range")
      }
      if next_time > time {
        state.sample(time * scale, clock, reset, watched)
        time = next_time
      }
    } else {
      match token.at(0) {
        36 =>
          match token {
            "$dumpvars" | "$dumpall" | "$end" => ()
            "$comment" => ignore(tokens.directive())
            _ => raise InvalidTrace("unsupported value directive \{token}")
          }
        114 | 82 | 115 | 83 =>
          if tokens.next() is None {
            raise InvalidTrace("missing value identifier")
          }
        98 | 66 =>
          match tokens.next() {
            Some(code) =>
              if widths.get(code) is Some(width) {
                state.values[code] = normalize(token[1:].to_owned(), width)
              }
            None => raise InvalidTrace("missing vector identifier")
          }
        48 | 49 | 120 | 88 | 122 | 90 => {
          let code = token[1:].to_owned()
          if code.is_empty() {
            raise InvalidTrace("missing scalar identifier")
          }
          if widths.get(code) is Some(width) {
            state.values[code] = normalize(token[:1].to_owned(), width)
          }
        }
        _ => raise InvalidTrace("unrecognized value change")
      }
    }
  }
  state.sample(time * scale, clock, reset, watched)
  if state.samples.is_empty() {
    raise InvalidTrace("no rising edge after observed reset")
  }
  {
    signals: names.copy(),
    widths: watched.map(signal => signal.width),
    samples: state.samples,
  }
}

///|
pub fn compare(baseline : Trace, run : Trace) -> Comparison raise TraceError {
  if baseline.signals != run.signals {
    raise InvalidTrace("traces select different signals")
  }
  if baseline.widths != run.widths {
    raise InvalidTrace("selected signal widths differ between traces")
  }
  let count = if baseline.samples.length() < run.samples.length() {
    baseline.samples.length()
  } else {
    run.samples.length()
  }
  for index in 0..<count {
    let expected = baseline.samples[index]
    let actual = run.samples[index]
    for i, name in baseline.signals {
      if expected.values[i] != actual.values[i] {
        return Different(
          index + 1,
          name,
          expected.values[i],
          actual.values[i],
          expected.time_fs,
          actual.time_fs,
        )
      }
    }
  }
  if baseline.samples.length() != run.samples.length() {
    LengthMismatch(baseline.samples.length(), run.samples.length())
  } else {
    Match(count)
  }
}
