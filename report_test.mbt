///|
fn report_traces() -> (@vcd-regression.Trace, @vcd-regression.Trace) raise {
  let base_text = waveform("1ns", 2, 1, "10").replace_all(
    old="$upscope $end",
    new="$var wire 4 c mirror $end\n$upscope $end",
  )
  let changed = base_text
    .replace_all(old="b1 c", new="b11 c")
    .replace_all(old="b10 c", new="b11 c")
  let names = ["tb.q", "tb.mirror"]
  (
    @vcd-regression.capture(base_text, "tb.clk", "tb.rst_n", names),
    @vcd-regression.capture(changed, "tb.clk", "tb.rst_n", names),
  )
}

///|
test "report retains a bounded list but scans all cycles and signals" {
  let (base, changed) = report_traces()
  let report = @vcd-regression.regression_report(
    base,
    changed,
    max_differences=1,
  )
  assert_eq(report.status, "different")
  assert_eq(report.compared_cycles, 2)
  assert_eq(report.differing_cycles, 2)
  assert_eq(report.difference_count, 4L)
  assert_eq(report.differences.length(), 1)
  assert_true(report.truncated)
  assert_eq(report.differences[0].cycle, 1)
  assert_eq(report.differences[0].signal, "tb.q")
  assert_eq(report.signals[1].differing_cycles, 2)
  assert_eq(report.signals[1].first_cycle, Some(1))
  assert_eq(report.signals[1].last_cycle, Some(2))
  assert_true(
    report.to_text().contains("statistics cover the full selected window"),
  )
}

///|
test "window keeps absolute cycle numbers and exact end boundaries" {
  let (base, changed) = report_traces()
  let report = @vcd-regression.regression_report(
    base,
    changed,
    skip_cycles=1,
    cycles=1,
  )
  assert_eq(report.start_cycle, 2)
  assert_eq(report.compared_cycles, 1)
  assert_eq(report.difference_count, 2L)
  assert_eq(report.differences[0].cycle, 2)
  assert_eq(report.signals[0].first_cycle, Some(2))
  assert_true(!report.truncated)
  let match_report = @vcd-regression.regression_report(base, base, cycles=1)
  assert_eq(match_report.status, "match")
  assert_eq(match_report.difference_count, 0L)
  assert_eq(match_report.signals[0].first_cycle, None)
}

///|
test "length mismatch is reported even when a common prefix matches" {
  let text = waveform("1ns", 2, 1, "10")
  let base = @vcd-regression.capture(text, "tb.clk", "tb.rst_n", ["tb.q"])
  let longer = @vcd-regression.capture(
    text + "#7 1a b10 c\n#8 0a\n",
    "tb.clk",
    "tb.rst_n",
    ["tb.q"],
  )
  let report = @vcd-regression.regression_report(base, longer)
  assert_eq(report.status, "length_mismatch")
  assert_eq(report.baseline_cycles, 2)
  assert_eq(report.candidate_cycles, 3)
  assert_eq(report.compared_cycles, 2)
  assert_eq(report.difference_count, 0L)
  // A deliberately bounded prefix does not claim to check the omitted tail.
  assert_eq(
    @vcd-regression.regression_report(base, longer, cycles=2).status,
    "match",
  )
}

///|
test "invalid windows and limits cannot silently pass" {
  let (base, _) = report_traces()
  for (skip, count, cap) in [(-1, 1, 1), (0, 0, 1), (0, 1, 0), (2, 1, 1)] {
    try
      @vcd-regression.regression_report(
        base,
        base,
        skip_cycles=skip,
        cycles=count,
        max_differences=cap,
      )
    catch {
      error => assert_true(error is @vcd-regression.InvalidTrace(_))
    } noraise {
      _ => fail("invalid window must not produce a passing report")
    }
  }
}

///|
test "portable JSON preserves counters timestamps and escaped error messages" {
  let (base, changed) = report_traces()
  let parsed = @json.parse(
    @vcd-regression.regression_report(base, changed).to_json(),
  )
  guard parsed is Object(fields) else { fail("expected JSON object") }
  assert_eq(fields.get("difference_count"), Some(Json::string("4")))
  guard fields.get("differences") is Some(Array(items)) else {
    fail("expected differences")
  }
  guard items[0] is Object(difference) else { fail("expected difference") }
  assert_eq(difference.get("baseline_fs"), Some(Json::string("3000000")))
  let message = "quote\" newline\nslash\\ control\t"
  let invalid = @json.parse(@vcd-regression.invalid_json(message))
  guard invalid is Object(error_fields) else { fail("expected error object") }
  assert_eq(error_fields.get("message"), Some(Json::string(message)))
  let matching = @json.parse(@vcd-regression.comparison_json(Match(2)))
  guard matching is Object(matching_fields) else {
    fail("expected matching object")
  }
  assert_eq(matching_fields.get("status"), Some(Json::string("match")))
  assert_eq(matching_fields.get("cycles"), Some(@json.to_json(2)))
}
