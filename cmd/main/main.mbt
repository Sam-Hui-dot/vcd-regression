///|
extern "js" fn read_text(path : String) -> String =
  #|(path) => {
  #|  try { return process.getBuiltinModule("node:fs").readFileSync(path, "utf8"); }
  #|  catch (error) { console.error(error.message); process.exit(2); }
  #|}

///|
extern "js" fn exit_with(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
extern "js" fn json_result(
  status : String,
  cycles : Int32,
  signal : String,
  expected : String,
  actual : String,
  baseline_fs : String,
  candidate_fs : String,
  message : String,
) -> String =
  #|(status, cycles, signal, expected, actual, baseline_fs, candidate_fs, message) => JSON.stringify({status, cycles, signal, expected, actual, baseline_fs, candidate_fs, message})

///|
fn main {
  let args = @env.args()
  let json_output = args.length() > 2 && args[2] == "--json"
  let start = if json_output { 3 } else { 2 }
  if args.length() < start + 5 {
    println(
      "Usage: vcd-regression [--json] BASE.vcd RUN.vcd CLOCK RESET_N SIGNAL [SIGNAL ...]",
    )
    exit_with(2)
    return
  }
  let names = args[start + 4:].to_owned()
  try {
    let base = @trace.capture(
      read_text(args[start]),
      args[start + 2],
      args[start + 3],
      names,
    )
    let run = @trace.capture(
      read_text(args[start + 1]),
      args[start + 2],
      args[start + 3],
      names,
    )
    match @trace.compare(base, run) {
      @trace.Match(count) =>
        if json_output {
          println(json_result("match", count, "", "", "", "", "", ""))
        } else {
          println("PASS: \{count} sampled cycles")
        }
      @trace.Different(cycle, signal, expected, actual, base_fs, run_fs) => {
        if json_output {
          println(
            json_result(
              "different",
              cycle,
              signal,
              expected,
              actual,
              base_fs.to_string(),
              run_fs.to_string(),
              "",
            ),
          )
        } else {
          println(
            "FAIL cycle \{cycle}, \{signal}: expected \{expected} at \{base_fs} fs, got \{actual} at \{run_fs} fs",
          )
        }
        exit_with(1)
      }
      @trace.LengthMismatch(expected, actual) => {
        if json_output {
          println(
            json_result(
              "length_mismatch",
              0,
              "",
              expected.to_string(),
              actual.to_string(),
              "",
              "",
              "",
            ),
          )
        } else {
          println("FAIL sample count: expected \{expected}, got \{actual}")
        }
        exit_with(1)
      }
    }
  } catch {
    @trace.InvalidTrace(message) => {
      if json_output {
        println(json_result("invalid", 0, "", "", "", "", "", message))
      } else {
        println("Invalid VCD: \{message}")
      }
      exit_with(2)
    }
  }
}
