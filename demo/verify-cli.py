"""Check machine-readable CLI results and exit statuses using shipped VCD fixtures."""
import json
from pathlib import Path
import subprocess
import sys

cli = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parent
common = ["tb_hex_counter_top.clk", "tb_hex_counter_top.rst_n", "tb_hex_counter_top.count"]
for variant, expected_status, expected_code in [("equivalent", "match", 0), ("faulty", "different", 1)]:
    result = subprocess.run(["node", str(cli), "--json", str(root / "baseline.vcd"),
                             str(root / (variant + ".vcd")), *common], capture_output=True, text=True)
    assert result.returncode == expected_code, result.stderr
    report = json.loads(result.stdout)
    assert report["status"] == expected_status, report
    if expected_status == "different":
        assert report["cycles"] == 828 and report["signal"] == common[-1], report
        assert report["baseline_fs"] == "8305000000", report
        assert report["expected"] == "1111" and report["actual"] == "0000", report
    else:
        assert report["cycles"] == 986, report
# Selected signal errors must also be parseable and preserve the invalid-input exit code.
result = subprocess.run(["node", str(cli), "--json", str(root / "baseline.vcd"),
                         str(root / "equivalent.vcd"), *common, common[-1]], capture_output=True, text=True)
assert result.returncode == 2, result
assert json.loads(result.stdout)["status"] == "invalid", result.stdout
usage = subprocess.run(["node", str(cli)], capture_output=True, text=True)
assert usage.returncode == 2 and "Usage:" in usage.stdout, usage
print("CLI JSON match, difference, invalid input and usage checks passed")
