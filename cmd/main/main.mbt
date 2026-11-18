///|
suberror ArgumentError {
  InvalidArgument(String)
}

///|
extern "js" fn read_text(path : String) -> String =
  #|(path) => {
  #|  try { return process.getBuiltinModule("node:fs").readFileSync(path, "utf8"); }
  #|  catch (error) { console.error(error.message); process.exit(2); }
  #|}

///|
extern "js" fn exit_with(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
struct Options {
  json_output : Bool
  report : Bool
  skip_cycles : Int32
  cycles : Int32?
  max_differences : Int32
  mapped_outputs : Array[(String, String)]
  inputs : Array[(String, String)]
  candidate_clock : String?
  candidate_reset : String?
  files_at : Int32
}

///|
fn usage() -> Unit {
  println(
    "Usage: vcd-regression [OPTIONS] BASE.vcd RUN.vcd CLOCK RESET_N [SIGNAL ...]",
  )
  println("  --json             Emit machine-readable JSON")
  println("  --report           Compare the whole window and emit a summary")
  println("  --skip-cycles N    Skip N post-reset sampled cycles (default 0)")
  println("  --cycles N         Compare at most N cycles after skipping")
  println(
    "  --max-diffs N      Retain at most N differing signal values (default 100)",
  )
  println("  --help             Show this help")
  println("  --map BASE RUN     Compare two output paths (repeatable)")
  println("  --input BASE RUN   Precheck two input paths (repeatable)")
  println("  --candidate-clock PATH   Override the candidate clock path")
  println(
    "  --candidate-reset PATH   Override the candidate low-active reset path",
  )
  println(
    "Window and limit options enable report mode; cycle numbers remain absolute.",
  )
}

///|
fn path_option(
  args : Array[String],
  index : Int32,
  offset : Int32,
) -> String raise ArgumentError {
  if index + offset >= args.length() || args[index + offset].has_prefix("--") {
    raise InvalidArgument("missing path for \{args[index]}")
  }
  args[index + offset]
}

///|
fn number_option(
  args : Array[String],
  index : Int32,
) -> Int32 raise ArgumentError {
  if index + 1 >= args.length() {
    raise InvalidArgument("missing value for \{args[index]}")
  }
  @string.parse_int(args[index + 1][:]) catch {
    _ => raise InvalidArgument("invalid integer for \{args[index]}")
  }
}

///|
fn options(args : Array[String]) -> Options raise ArgumentError {
  let mut index = 2
  let mut json_output = false
  let mut report = false
  let mut skip_cycles = 0
  let mut cycles : Int32? = None
  let mut max_differences = 100
  let mapped_outputs = []
  let inputs = []
  let mut candidate_clock = None
  let mut candidate_reset = None
  while index < args.length() {
    match args[index] {
      "--" => {
        index += 1
        break
      }
      "--json" => {
        json_output = true
        index += 1
      }
      "--report" => {
        report = true
        index += 1
      }
      "--skip-cycles" => {
        skip_cycles = number_option(args, index)
        report = true
        index += 2
      }
      "--cycles" => {
        cycles = Some(number_option(args, index))
        report = true
        index += 2
      }
      "--max-diffs" => {
        max_differences = number_option(args, index)
        report = true
        index += 2
      }
      "--map" | "--input" as flag => {
        let pair = (path_option(args, index, 1), path_option(args, index, 2))
        if flag == "--map" {
          mapped_outputs.push(pair)
        } else {
          inputs.push(pair)
        }
        index += 3
      }
      "--candidate-clock" => {
        candidate_clock = Some(path_option(args, index, 1))
        index += 2
      }
      "--candidate-reset" => {
        candidate_reset = Some(path_option(args, index, 1))
        index += 2
      }
      value => {
        if value.has_prefix("--") {
          raise InvalidArgument("unknown option: \{value}")
        }
        break
      }
    }
  }
  if args.length() < index + 4 ||
    (args.length() == index + 4 && mapped_outputs.is_empty()) {
    raise InvalidArgument(
      "expected two VCD files, clock, reset and at least one signal",
    )
  }
  if skip_cycles < 0 || max_differences <= 0 {
    raise InvalidArgument(
      "skip must be nonnegative and max-diffs must be positive",
    )
  }
  if cycles is Some(count) && count <= 0 {
    raise InvalidArgument("cycles must be positive")
  }
  {
    json_output,
    report,
    skip_cycles,
    cycles,
    max_differences,
    mapped_outputs,
    inputs,
    candidate_clock,
    candidate_reset,
    files_at: index,
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() == 3 && args[2] == "--help" {
    usage()
    return
  }
  if args.length() < 3 {
    usage()
    exit_with(2)
    return
  }
  // This fallback also covers a malformed option before --json.
  let wants_json = args.contains("--json")
  try {
    let config = options(args)
    let start = config.files_at
    let outputs = config.mapped_outputs +
      args[start + 4:].to_owned().map(path => (path, path))
    let clock = args[start + 2]
    let reset = args[start + 3]
    let pair = @trace.capture_pair(
      read_text(args[start]),
      read_text(args[start + 1]),
      (clock, config.candidate_clock.unwrap_or(clock)),
      (reset, config.candidate_reset.unwrap_or(reset)),
      outputs,
      inputs=config.inputs,
    )
    match pair.check_stimulus() {
      None | Some(@trace.StimulusMatch(_)) => ()
      Some(check) => {
        println(
          if config.json_output {
            check.to_json()
          } else {
            check.to_text()
          },
        )
        exit_with(3)
        return
      }
    }
    let base = pair.baseline
    let run = pair.candidate
    if config.report {
      let report = @trace.regression_report(
        base,
        run,
        skip_cycles=config.skip_cycles,
        cycles?=config.cycles,
        max_differences=config.max_differences,
      )
      println(
        if config.json_output {
          report.to_json()
        } else {
          report.to_text()
        },
      )
      if report.status != "match" {
        exit_with(1)
      }
      return
    }
    let result = @trace.compare(base, run)
    if config.json_output {
      println(@trace.comparison_json(result))
    }
    match result {
      @trace.Match(count) =>
        if !config.json_output {
          println("PASS: \{count} sampled cycles")
        }
      @trace.Different(cycle, signal, expected, actual, base_fs, run_fs) => {
        if !config.json_output {
          println(
            "FAIL cycle \{cycle}, \{signal}: expected \{expected} at \{base_fs} fs, got \{actual} at \{run_fs} fs",
          )
        }
        exit_with(1)
      }
      @trace.LengthMismatch(expected, actual) => {
        if !config.json_output {
          println("FAIL sample count: expected \{expected}, got \{actual}")
        }
        exit_with(1)
      }
    }
  } catch {
    InvalidArgument(message) => {
      println(
        if wants_json {
          @trace.invalid_json(message)
        } else {
          "Invalid arguments: \{message}"
        },
      )
      exit_with(2)
    }
    @trace.InvalidTrace(message) => {
      println(
        if wants_json {
          @trace.invalid_json(message)
        } else {
          "Invalid VCD: \{message}"
        },
      )
      exit_with(2)
    }
    error => {
      println(
        if wants_json {
          @trace.invalid_json(error.to_string())
        } else {
          error.to_string()
        },
      )
      exit_with(2)
    }
  }
}
