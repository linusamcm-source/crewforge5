#!/usr/bin/env bash
# functional.sh <skill-path> — mechanical Step 2 (functional) checks left over
# after validate_structure.sh: Python dependency dry-runs and references/ validity.
# Emits FAIL/WARN findings lines. Always exits 0 — grade.sh does the judging.
set -euo pipefail

DIR="${1:?usage: functional.sh <skill-path>}"

exec python3 - "$DIR" <<'PY'
import importlib.util, json, pathlib, re, sys

d = pathlib.Path(sys.argv[1])
findings = []

# Python scripts: parse AST, dry-run each top-level import (missing-dep check).
for py in sorted((d / "scripts").glob("*.py")) if (d / "scripts").is_dir() else []:
    try:
        import ast
        tree = ast.parse(py.read_text(encoding="utf-8"))
    except SyntaxError as e:
        findings.append(f"FAIL [functional]: {py.name} syntax error: {e.msg} (line {e.lineno})")
        continue
    mods = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            mods |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            mods.add(node.module.split(".")[0])
    for m in sorted(mods):
        if importlib.util.find_spec(m) is None:
            findings.append(f"WARN [functional]: {py.name} imports '{m}' — not installed in this environment")

# references/: non-empty, parseable JSON/YAML, long files need section headers.
ref = d / "references"
if ref.is_dir():
    for f in sorted(ref.rglob("*")):
        if not f.is_file():
            continue
        text = f.read_text(encoding="utf-8", errors="replace")
        if not text.strip():
            findings.append(f"FAIL [functional]: references/{f.relative_to(ref)} is empty")
            continue
        if f.suffix == ".json":
            try:
                json.loads(text)
            except ValueError as e:
                findings.append(f"FAIL [functional]: references/{f.relative_to(ref)} invalid JSON: {e}")
        if f.suffix in (".yaml", ".yml"):
            try:
                import yaml
                yaml.safe_load(text)
            except ImportError:
                findings.append(f"SKIPPED [functional]: pyyaml not installed, cannot parse {f.name}")
            except Exception as e:
                findings.append(f"FAIL [functional]: references/{f.relative_to(ref)} invalid YAML: {e}")
        n = text.count("\n") + 1
        if f.suffix == ".md" and n > 300 and not re.search(r"^#{2,3} ", text, re.MULTILINE):
            findings.append(f"WARN [functional]: references/{f.relative_to(ref)} is {n} lines with no ##/### section headers")

for f in findings:
    print(f)
if not findings:
    print("OK [functional]: all mechanical functional checks clean")
PY
