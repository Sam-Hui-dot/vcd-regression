///|
fn paired_fixture(
  text : String,
  candidate : String,
) -> @vcd-regression.TracePair raise {
  @vcd-regression.capture_pair(
    text,
    candidate,
    ("tb.clk", "tb.clk"),
    ("tb.rst_n", "tb.rst_n"),
    [("tb.q", "tb.q")],
    inputs=[("tb.q", "tb.q")],
  )
}

///|
test "a signal can be explicitly selected as both stimulus and observation" {
  let text = waveform("1ns", 2, 1, "10")
  let pair = paired_fixture(text, text)
  assert_true(pair.check_stimulus() is Some(@vcd-regression.StimulusMatch(2)))
  assert_eq(@vcd-regression.compare(pair.baseline, pair.candidate), Match(2))
}

///|
test "equal unknown sampled inputs do not establish equal stimuli" {
  let text = waveform("1ns", 2, 1, "x")
  let pair = paired_fixture(text, text)
  assert_true(
    pair.check_stimulus()
    is Some(@vcd-regression.StimulusUnknown(2, "tb.q", "xxxx", "xxxx")),
  )
}

///|
test "input precheck catches an unmatched tail and mapped width mismatches" {
  let text = waveform("1ns", 2, 1, "10")
  let longer = text + "#7 1a b10 c\n#8 0a\n"
  assert_true(
    paired_fixture(text, longer).check_stimulus()
    is Some(@vcd-regression.StimulusLengthMismatch(2, 3)),
  )
  let wider = text.replace_all(old="$var wire 4 c", new="$var wire 5 c")
  let pair = paired_fixture(text, wider)
  try pair.check_stimulus() catch {
    error =>
      assert_true(
        error
        is @vcd-regression.InvalidTrace(
          "mapped input signal widths differ between traces"
        ),
      )
  } noraise {
    _ => fail("mapped input widths must agree")
  }
}
