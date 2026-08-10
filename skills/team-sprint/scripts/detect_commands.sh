#!/usr/bin/env bash
# detect_commands.sh — auto-detect typecheck/lint/test/coverage commands for a
# project. Story mech-7 deliverable.
#
# Usage:
#   detect_commands.sh [<project_dir>]
#
# Emits JSON on stdout:
#   {
#     "typecheck":  "...",
#     "lint":       "...",
#     "test":       "...",
#     "coverage":   "...",
#     "stack":      "node|go|python|rust|bash|mixed",
#     "confidence": "high|medium|low",
#     "ambiguities":["..."]
#   }
#
# Command-source priority (highest first):
#   1. team-sprint.config.yaml -> commands.<target>  (explicit-config precedence)
#   2. justfile
#   3. package.json (scripts.<target>)
#   4. Makefile
#   5. pyproject.toml (tool.poetry.scripts / [project.scripts] / tool.pdm.scripts / tool.rye.scripts)
#   6. Cargo.toml
#   7. go.mod
#
# Stack inference uses language-marker files only:
#   package.json -> node
#   pyproject.toml -> python
#   Cargo.toml -> rust
#   go.mod -> go
# More than one from different families -> "mixed".
# None present -> "bash".
#
# Confidence rules:
#   high   = all four targets resolved AND stack != "mixed"
#   medium = at least one but not all four targets resolved AND stack != "mixed"
#   low    = no targets resolved
#   When stack == "mixed", confidence is "low" regardless of target resolution
#   (lead is forced to ask the user which language to pick).
#
# Explicit-config precedence: a target supplied by team-sprint.config.yaml is
# always counted as resolved and contributes to "high" — even if the
# auto-detected file is missing that target.
#
# Exit 0 on success (always — low/mixed surface via the JSON payload, not via
# exit code). Exit 1 only on internal failure.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_python3 || exit 1   # all JSON here is json.dumps in the embedded core; no jq

PROJECT_DIR="${1:-$PWD}"
[[ -d "$PROJECT_DIR" ]] || fail "detect_commands.sh: not a directory: $PROJECT_DIR"

# Resolve to absolute path so the python core doesn't have to worry about CWD.
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

CONFIG_FILE="${TEAM_SPRINT_CONFIG:-$PROJECT_DIR/team-sprint.config.yaml}"

# team-sprint.config.yaml commands.<target> overrides, read via the shared
# lib.sh reader (deduped in Story LS4) and passed into the detector as argv.
{ IFS= read -r CFG_TYPECHECK
  IFS= read -r CFG_LINT
  IFS= read -r CFG_TEST
  IFS= read -r CFG_COVERAGE
} < <(read_config_commands "$CONFIG_FILE" typecheck lint test coverage)

python3 - "$PROJECT_DIR" "$CFG_TYPECHECK" "$CFG_LINT" "$CFG_TEST" "$CFG_COVERAGE" <<'PY'
import json
import os
import re
import sys

project_dir = sys.argv[1]

# ---------------------------------------------------------------------------
# 1. Explicit-config precedence: non-empty, non-"null" commands.<target>
#    values supplied by team-sprint.config.yaml (read via lib.sh
#    read_config_command and passed in as argv[2:6], in
#    typecheck/lint/test/coverage order).
# ---------------------------------------------------------------------------
config_cmds = {
    key: val
    for key, val in zip(("typecheck", "lint", "test", "coverage"), sys.argv[2:6])
    if val and val.lower() != "null"
}


# ---------------------------------------------------------------------------
# 2. Stack-marker file detection.
# ---------------------------------------------------------------------------
def detect_stack(pdir):
    """Return (stack, marker_files) where marker_files is the list of marker
    files actually present (used for mixed detection)."""
    markers = []
    if os.path.isfile(os.path.join(pdir, "package.json")):
        markers.append(("node", "package.json"))
    if os.path.isfile(os.path.join(pdir, "pyproject.toml")):
        markers.append(("python", "pyproject.toml"))
    if os.path.isfile(os.path.join(pdir, "Cargo.toml")):
        markers.append(("rust", "Cargo.toml"))
    if os.path.isfile(os.path.join(pdir, "go.mod")):
        markers.append(("go", "go.mod"))
    if not markers:
        return "bash", []
    families = sorted({m[0] for m in markers})
    if len(families) > 1:
        return "mixed", markers
    return families[0], markers


# ---------------------------------------------------------------------------
# 3. justfile target extraction. justfile recipes look like:
#       recipe-name:
#       recipe-name arg:
#       recipe-name:    # comment
#   We treat each recipe NAME as a command runnable as `just <name>`.
# ---------------------------------------------------------------------------
def parse_justfile(pdir):
    path = os.path.join(pdir, "justfile")
    if not os.path.isfile(path):
        return {}
    targets = {}
    recipe_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_\-]*)\s*(?:[A-Za-z0-9_\-\s+=*]*)?:\s*(?:#.*)?$")
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            # Skip indented (recipe-body), assignments, and comments.
            if not line or line.startswith((" ", "\t", "#")):
                continue
            if "=" in line and ":" not in line.split("=", 1)[0]:
                continue
            m = recipe_re.match(line)
            if not m:
                continue
            name = m.group(1)
            if name in ("typecheck", "lint", "test", "coverage"):
                targets[name] = f"just {name}"
    return targets


# ---------------------------------------------------------------------------
# 4. package.json scripts extraction.
# ---------------------------------------------------------------------------
def parse_package_json(pdir):
    path = os.path.join(pdir, "package.json")
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return {}
    scripts = data.get("scripts", {}) or {}
    if not isinstance(scripts, dict):
        return {}
    out = {}
    for key in ("typecheck", "lint", "test", "coverage"):
        if key in scripts and isinstance(scripts[key], str) and scripts[key].strip():
            out[key] = f"npm run {key}"
    return out


# ---------------------------------------------------------------------------
# 5. Makefile target extraction. Looks for "^<name>:" at start of line.
# ---------------------------------------------------------------------------
def parse_makefile(pdir):
    path = os.path.join(pdir, "Makefile")
    if not os.path.isfile(path):
        return {}
    targets = {}
    # Strict Makefile target: name followed by `:` (with optional deps but no
    # `=` before the colon, which would be an assignment).
    tgt_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_\-]*)\s*:")
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line or line.startswith(("\t", "#", " ")):
                continue
            # Skip variable assignments (e.g. "FOO := bar").
            if re.match(r"^[A-Za-z_][A-Za-z0-9_\-]*\s*[:?+]?=", line):
                continue
            m = tgt_re.match(line)
            if not m:
                continue
            name = m.group(1)
            if name in ("typecheck", "lint", "test", "coverage"):
                targets[name] = f"make {name}"
    return targets


# ---------------------------------------------------------------------------
# 6. pyproject.toml — look for [tool.poetry.scripts], [project.scripts],
#    [tool.pdm.scripts], [tool.rye.scripts]. Best-effort line-based parse to
#    avoid depending on tomllib (py3.11+).
# ---------------------------------------------------------------------------
def parse_pyproject(pdir):
    path = os.path.join(pdir, "pyproject.toml")
    if not os.path.isfile(path):
        return {}
    out = {}
    section = ""
    scripts_sections = {
        "tool.poetry.scripts", "project.scripts",
        "tool.pdm.scripts", "tool.rye.scripts",
    }
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^\[([^\]]+)\]$", line)
            if m:
                section = m.group(1).strip()
                continue
            if section not in scripts_sections:
                continue
            # key = "value" or key = "module:func"
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_\-]*)\s*=\s*(.+)$", line)
            if not m:
                continue
            key, val = m.group(1), m.group(2).strip()
            # Strip quotes if present.
            if val and val[0] in ('"', "'") and val.endswith(val[0]):
                val = val[1:-1]
            if key in ("typecheck", "lint", "test", "coverage") and val:
                # pyproject scripts get invoked by the relevant tool runner.
                # Without knowing which (poetry/pdm/rye), emit the script name
                # itself as the command — runnable from a venv. The lead can
                # override via team-sprint.config.yaml if a runner prefix is
                # required.
                out[key] = key
    return out


# ---------------------------------------------------------------------------
# 7. Cargo.toml — assumes presence implies the rust default targets.
# ---------------------------------------------------------------------------
def parse_cargo(pdir):
    path = os.path.join(pdir, "Cargo.toml")
    if not os.path.isfile(path):
        return {}
    return {
        "typecheck": "cargo check",
        "lint":      "cargo clippy --all-targets -- -D warnings",
        "test":      "cargo test",
    }


# ---------------------------------------------------------------------------
# 8. go.mod — assumes presence implies the go default targets.
# ---------------------------------------------------------------------------
def parse_gomod(pdir):
    path = os.path.join(pdir, "go.mod")
    if not os.path.isfile(path):
        return {}
    return {
        "typecheck": "go build ./...",
        "lint":      "go vet ./...",
        "test":      "go test ./...",
        "coverage":  "go test -coverprofile=coverage.out ./...",
    }


# ---------------------------------------------------------------------------
# Composition: walk the command-source priority list, filling each target
# from the first source that defines it.
# ---------------------------------------------------------------------------
stack, markers = detect_stack(project_dir)

just_cmds = parse_justfile(project_dir)
pkg_cmds  = parse_package_json(project_dir)
mk_cmds   = parse_makefile(project_dir)
py_cmds   = parse_pyproject(project_dir)
cargo_cmds = parse_cargo(project_dir)
go_cmds   = parse_gomod(project_dir)

source_chain = [
    ("justfile",       just_cmds),
    ("package.json",   pkg_cmds),
    ("Makefile",       mk_cmds),
    ("pyproject.toml", py_cmds),
    ("Cargo.toml",     cargo_cmds),
    ("go.mod",         go_cmds),
]

result = {"typecheck": "", "lint": "", "test": "", "coverage": ""}

# Explicit-config precedence wins first.
for key in result:
    if key in config_cmds:
        result[key] = config_cmds[key]

# Fill remaining targets from the priority chain.
for _, cmds in source_chain:
    for key in result:
        if not result[key] and key in cmds:
            result[key] = cmds[key]

# Ambiguities: target left empty after all sources, OR mixed stack.
ambiguities = []
unresolved = [k for k, v in result.items() if not v]
for k in unresolved:
    ambiguities.append(f"{k} command not detected; set commands.{k} in team-sprint.config.yaml or ask the user")

if stack == "mixed":
    fams = sorted({m[0] for m in markers})
    ambiguities.append(
        f"multiple language markers present ({', '.join(fams)}); pick one or split into sub-projects"
    )

# Confidence rules.
if stack == "mixed":
    confidence = "low"
elif not unresolved:
    confidence = "high"
elif len(unresolved) == 4:
    confidence = "low"
else:
    confidence = "medium"

out = {
    "typecheck":   result["typecheck"],
    "lint":        result["lint"],
    "test":        result["test"],
    "coverage":    result["coverage"],
    "stack":       stack,
    "confidence":  confidence,
    "ambiguities": ambiguities,
}

sys.stdout.write(json.dumps(out, sort_keys=True) + "\n")
PY
