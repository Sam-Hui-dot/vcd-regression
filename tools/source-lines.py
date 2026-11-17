"""Count non-test MoonBit code, excluding blank/comment-only lines and JS FFI bodies.

This is a reproducible source inventory, not a claim about the organizer's counting tool.
The implementation uses line comments only; fail rather than miscount block comments.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
files = []
for path in sorted(root.rglob("*.mbt")):
    relative = path.relative_to(root)
    if any(part in {"_build", ".git", ".mooncakes", "vendor", "third_party"} for part in relative.parts):
        continue
    if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
        continue
    lines = path.read_text(encoding="utf-8").splitlines()
    code = blank = comments = foreign = 0
    for line in lines:
        stripped = line.strip()
        if not stripped:
            blank += 1
        elif stripped.startswith("//"):
            comments += 1
        elif stripped.startswith("#|"):
            foreign += 1
        else:
            if "/*" in stripped:
                raise ValueError("Block comments need lexical counting: " + str(relative))
            code += 1
    files.append({"file": relative.as_posix(), "physical": len(lines), "code": code,
                  "blank": blank, "comment_only": comments, "foreign_body": foreign})
result = {"method": "non-test .mbt, excluding blank/comment-only/JS FFI body lines",
          "files": files, "code_total": sum(item["code"] for item in files),
          "library_code": sum(item["code"] for item in files if not item["file"].startswith("cmd/"))}
print(json.dumps(result, ensure_ascii=False, indent=2))
assert result["library_code"] >= 500, "Core MoonBit library must exceed 500 code lines"
assert result["code_total"] >= 650, "Keep margin above the 500-line admission threshold"
