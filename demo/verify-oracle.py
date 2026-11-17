import argparse
import bisect
import json
import subprocess
from pathlib import Path
from vcdvcd import VCDVCD

parser = argparse.ArgumentParser()
parser.add_argument("cli", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent


def normalized(value, width):
    value = value.lower()
    return value.rjust(width, value[0] if value[0] in "xz" else "0")


def samples(path, clock, reset, signals):
    trace = VCDVCD(str(path), signals=[clock, reset] + signals)
    watched = [trace[signal] for signal in signals]
    times = [[point[0] for point in signal.tv] for signal in watched]
    reset_times = [point[0] for point in trace[reset].tv]
    seen_reset_at = next(time for time, value in trace[reset].tv if value == "0")
    previous = "x"
    result = []
    for time, clock_value in trace[clock].tv:
        reset_index = bisect.bisect_right(reset_times, time) - 1
        reset_value = trace[reset].tv[reset_index][1] if reset_index >= 0 else "x"
        if previous == "0" and clock_value == "1" and time >= seen_reset_at and reset_value == "1":
            values = []
            for signal, timestamps in zip(watched, times):
                index = bisect.bisect_right(timestamps, time) - 1
                value = signal.tv[index][1] if index >= 0 else "x"
                values.append(normalized(value, int(signal.size)))
            result.append((time, values))
        previous = clock_value
    return result


cases = [
    (root, "tb_hex_counter_top", ["count"]),
    (root / "uart", "tb_uart", ["txd", "busy", "ready"]),
]
receipts = []
for folder, scope, names in cases:
    clock, reset = scope + ".clk", scope + ".rst_n"
    signals = [scope + "." + name for name in names]
    # Vector references may carry an optional [msb:lsb] suffix in VCDVCD.
    header = VCDVCD(str(folder / "baseline.vcd"), only_sigs=True)
    reference_names = []
    for signal in signals:
        matches = [name for name in header.signals if name == signal or name.startswith(signal + "[")]
        assert len(matches) == 1, matches
        reference_names.append(matches[0])
    base = samples(folder / "baseline.vcd", clock, reset, reference_names)
    for variant in ("equivalent", "faulty"):
        run = samples(folder / (variant + ".vcd"), clock, reset, reference_names)
        assert len(base) == len(run)
        first = next(
            ((cycle + 1, signal, expected, actual)
             for cycle, (left, right) in enumerate(zip(base, run))
             for signal, expected, actual in zip(signals, left[1], right[1])
             if expected != actual),
            None,
        )
        result = subprocess.run(
            ["node", str(args.cli), str(folder / "baseline.vcd"),
             str(folder / (variant + ".vcd")), clock, reset] + signals,
            capture_output=True, text=True,
        )
        assert (first is not None) == (variant == "faulty"), (scope, variant, first)
        assert result.returncode == (1 if first else 0), result.stdout + result.stderr
        if first:
            cycle, signal, expected, actual = first
            assert f"FAIL cycle {cycle}, {signal}: expected {expected}" in result.stdout
            assert f"got {actual} " in result.stdout
        else:
            assert f"PASS: {len(base)} sampled cycles" in result.stdout
        # Independently enumerate ALL differing values, then check bounded reports.
        expected_diffs = [
            (cycle + 1, signal, expected, actual)
            for cycle, (left, right) in enumerate(zip(base, run))
            for signal, expected, actual in zip(signals, left[1], right[1])
            if expected != actual
        ]
        for skip, limit in [(0, len(base)), (max(0, first[0] - 2) if first else 0, 5)]:
            selected = [row for row in expected_diffs if skip < row[0] <= skip + limit]
            process = subprocess.run(
                ["node", str(args.cli), "--report", "--json", "--max-diffs", "3",
                 "--skip-cycles", str(skip), "--cycles", str(limit),
                 str(folder / "baseline.vcd"), str(folder / (variant + ".vcd")),
                 clock, reset] + signals, capture_output=True, text=True,
            )
            assert process.returncode == (1 if selected else 0), process.stderr
            report = json.loads(process.stdout)
            assert report["difference_count"] == str(len(selected)), report
            assert report["differing_cycles"] == len({row[0] for row in selected}), report
            assert report["truncated"] == (len(selected) > 3), report
            assert [(d["cycle"], d["signal"], d["expected"], d["actual"])
                    for d in report["differences"]] == selected[:3], report
            for summary in report["signals"]:
                rows = [d for d in selected if d[1] == summary["signal"]]
                assert summary["differing_cycles"] == len(rows), summary
                assert summary["first_cycle"] == (rows[0][0] if rows else None), summary
                assert summary["last_cycle"] == (rows[-1][0] if rows else None), summary
        receipts.append({"design": scope, "variant": variant, "cycles": len(base),
                         "first_difference": first, "cli": result.stdout.strip()})
print(json.dumps(receipts, ensure_ascii=False, indent=2))

