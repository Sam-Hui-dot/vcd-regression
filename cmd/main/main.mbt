///|
extern "js" fn read_text(path : String) -> String =
  #|(path) => {
  #|  try { return process.getBuiltinModule("node:fs").readFileSync(path, "utf8"); }
  #|  catch (error) { console.error(error.message); process.exit(2); }
  #|}

///|
extern "js" fn exit_with(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
fn main {
  let args = @env.args()
  if args.length() < 7 {
    println(
      "Usage: vcd-regression BASE.vcd RUN.vcd CLOCK RESET_N SIGNAL [SIGNAL ...]",
    )
    exit_with(2)
    return
  }
  let names = args[6:].to_owned()
  try {
    let base = @trace.capture(read_text(args[2]), args[4], args[5], names)
    let run = @trace.capture(read_text(args[3]), args[4], args[5], names)
    match @trace.compare(base, run) {
      @trace.Match(count) => println("PASS: \{count} sampled cycles")
      @trace.Different(cycle, signal, expected, actual, base_fs, run_fs) => {
        println(
          "FAIL cycle \{cycle}, \{signal}: expected \{expected} at \{base_fs} fs, got \{actual} at \{run_fs} fs",
        )
        exit_with(1)
      }
      @trace.LengthMismatch(expected, actual) => {
        println("FAIL sample count: expected \{expected}, got \{actual}")
        exit_with(1)
      }
    }
  } catch {
    @trace.InvalidTrace(message) => {
      println("Invalid VCD: \{message}")
      exit_with(2)
    }
  }
}
