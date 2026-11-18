"""Build an independent MoonBit module against the public VCD library API."""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
workspace = root / "_build" / "consumer-check"
lib, app = workspace / "library", workspace / "consumer"
lib.mkdir(parents=True, exist_ok=True)
app.mkdir(parents=True, exist_ok=True)
for name in ("moon.mod", "moon.pkg", "vcd-regression.mbt", "report.mbt", "pair.mbt"):
    shutil.copyfile(root / name, lib / name)
(workspace / "moon.work").write_text('members = ["library", "consumer"]\n', encoding="utf-8")
(app / "moon.mod").write_text('name = "example/vcd-consumer"\npreferred_target = "js"\nimport { "Sam-Hui-dot/vcd-regression@0.4.0", }\n', encoding="utf-8")
(app / "moon.pkg").write_text('import { "Sam-Hui-dot/vcd-regression" @vcd, }\npkgtype(kind: "executable")\n', encoding="utf-8")
vcd = "$timescale 1ns $end\n$scope module tb $end\n$var wire 1 a clk $end\n$var wire 1 b rst_n $end\n$var wire 1 c q $end\n$upscope $end\n$enddefinitions $end\n$dumpvars 0a 0b 0c $end\n#1 1b\n#2 1a 1c\n#3 0a\n"
source = 'fn main raise {\n  let text = ' + json.dumps(vcd) + '\n  let left = @vcd.capture(text, "tb.clk", "tb.rst_n", ["tb.q"])\n  let right = @vcd.capture(text, "tb.clk", "tb.rst_n", ["tb.q"])\n  let pair = @vcd.capture_pair(text, text, ("tb.clk", "tb.clk"), ("tb.rst_n", "tb.rst_n"), [("tb.q", "tb.q")], inputs=[("tb.q", "tb.q")])\n  guard pair.check_stimulus() is Some(@vcd.StimulusMatch(1)) else { abort("unexpected stimulus") }\n  guard @vcd.compare(pair.baseline, pair.candidate) is @vcd.Match(1) else { abort("unexpected mapped result") }\n  match @vcd.compare(left, right) {\n    @vcd.Match(1) => println("consumer: match(1)")\n    _ => abort("unexpected comparison")\n  }\n}\n'
(app / "main.mbt").write_text(source, encoding="utf-8")
result = subprocess.run(["moon", "-C", str(app), "run", "."], capture_output=True, text=True, encoding="utf-8")
assert result.returncode == 0, result.stdout + result.stderr
assert "consumer: match(1)" in result.stdout, result.stdout
print("Independent module consumed capture/compare successfully")
