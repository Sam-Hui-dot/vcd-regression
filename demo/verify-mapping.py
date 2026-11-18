"""Exercise mapping and stimulus checks with renamed, recorded UART traces."""
import json
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory


def renamed(text):
    text = text.replace("$scope module tb_uart $end", "$scope module candidate $end", 1)
    substitutions = {
        "clk": "clock",
        "rst_n": "reset_n",
        "data": "input_data",
        "valid": "input_valid",
        "txd": "serial_out",
    }
    for before, after in substitutions.items():
        text, count = re.subn(r"(?m)^(\$var [^\n]* )" + before + r"(?= |$)",
                              lambda match: match.group(1) + after, text, count=1)
        assert count == 1, before
    return text


def run(cli, flags, baseline, candidate):
    process = subprocess.run(
        ["node", str(cli), "--json", *flags, str(baseline), str(candidate),
         "tb_uart.clk", "tb_uart.rst_n"],
        capture_output=True, text=True, encoding="utf-8",
    )
    assert process.stdout, process.stderr
    return process.returncode, json.loads(process.stdout)


def main():
    cli = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parent / "uart"
    baseline = root / "baseline.vcd"
    mappings = [
        "--candidate-clock", "candidate.clock",
        "--candidate-reset", "candidate.reset_n",
        "--map", "tb_uart.txd", "candidate.serial_out",
    ]
    inputs = [
        "--input", "tb_uart.data", "candidate.input_data",
        "--input", "tb_uart.valid", "candidate.input_valid",
    ]
    with TemporaryDirectory() as folder:
        candidate = Path(folder) / "candidate.vcd"
        candidate.write_text(renamed((root / "equivalent.vcd").read_text(encoding="utf-8")),
                             encoding="utf-8")
        code, report = run(cli, [*mappings, *inputs], baseline, candidate)
        assert (code, report["status"], report["cycles"]) == (0, "match", 664), report
        print("Renamed equivalent UART: 664 cycles match")

        text = renamed((root / "faulty.vcd").read_text(encoding="utf-8"))
        candidate.write_text(text, encoding="utf-8")
        code, report = run(cli, [*mappings, *inputs, "--report"], baseline, candidate)
        assert (code, report["status"]) == (1, "different"), report
        first = report["differences"][0]
        assert (first["cycle"], first["signal"], first["expected"], first["actual"]) == (
            146, "tb_uart.txd", "1", "0"
        ), first
        print("Renamed faulty UART: first output difference at cycle 146")

        # Change the first recorded input value to exercise rejection. This is a fixture
        # mutation, not a simulated design result with altered inputs.
        changed, count = re.subn(r"(?m)^b0 3$", "b11111111 3", text, count=1)
        assert count == 1
        candidate.write_text(changed, encoding="utf-8")
        code, report = run(cli, [*mappings, *inputs, "--skip-cycles", "145", "--cycles", "1"],
                           baseline, candidate)
        assert (code, report["status"]) == (3, "stimulus_mismatch"), report
        first = report["difference"]
        assert (first["cycle"], first["signal"], first["expected"], first["actual"]) == (
            1, "tb_uart.data", "00000000", "11111111"
        ), first
        assert "differences" not in report, report
        print("Mutated input: precheck stops comparison at cycle 1, outside output window")

        code, report = run(cli, [*mappings, *mappings], baseline, candidate)
        assert (code, report["status"]) == (2, "invalid"), report
        assert "duplicate output mapping" in report["message"], report


if __name__ == "__main__":
    main()
