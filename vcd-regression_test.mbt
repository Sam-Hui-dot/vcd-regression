///|
fn waveform(
  scale : String,
  delay : Int32,
  period : Int32,
  last_value : String,
) -> String {
  let first = delay + period
  let second = first + period
  let third = second + period
  let fourth = third + period
  "$timescale " +
  scale +
  " $end\n" +
  "$scope module tb $end\n$var wire 1 a clk $end\n$var wire 1 b rst_n $end\n$var wire 4 c q [3:0] $end\n$upscope $end\n$enddefinitions $end\n" +
  "$dumpvars\n0a 0b b0 c\n$end\n" +
  "#\{delay}\n1b\n#\{first}\n1a b1 c\n#\{second}\n0a\n#\{third}\n1a b\{last_value} c\n#\{fourth}\n0a\n"
}

///|
test "compare the same cycles even if timescale and reset time differ" {
  let base = @vcd-regression.capture(
    waveform("1ns", 2, 1, "10"),
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  let same = @vcd-regression.capture(
    waveform("100ps", 40, 10, "0010"),
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  assert_eq(@vcd-regression.compare(base, same), Match(2))
  let wrong = @vcd-regression.capture(
    waveform("100ps", 40, 10, "X"),
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  assert_eq(
    @vcd-regression.compare(base, wrong),
    Different(2, "tb.q", "0010", "xxxx", 5_000_000L, 7_000_000L),
  )
}

///|
test "changing a signal width cannot be reported as matching" {
  let base = @vcd-regression.capture(
    waveform("1ns", 2, 1, "10"),
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  let altered = @vcd-regression.capture(
    waveform("1ns", 2, 1, "10").replace_all(
      old="$var wire 4 c",
      new="$var wire 5 c",
    ),
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  try @vcd-regression.compare(base, altered) catch {
    error =>
      assert_true(
        error is InvalidTrace("selected signal widths differ between traces"),
      )
  } noraise {
    _ => fail("signal widths must match")
  }
}
