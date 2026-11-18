# Changelog

## 0.4.0

- Map baseline and candidate paths for outputs, clocks, resets and stimulus inputs.
- Stop output comparison when configured stimulus samples differ, contain X/Z, or have unequal lengths.
- Verify both features with the recorded UART traces and explicit fixture mutations.

## 0.3.0

- Add cycle-window regression reports with bounded detail lists and full-window statistics.
- Report per-signal differing-cycle counts and first/last cycles.
- Add portable MoonBit JSON/text serialization, preserving 64-bit fields as strings.
- Add report/window/limit CLI flags and argument diagnostics; retain the original output mode.
- Cross-check full reports against an independent VCD parser and add source inventory checks.
