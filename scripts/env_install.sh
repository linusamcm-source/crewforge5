#!/usr/bin/env bash
# env_install.sh — publish CREWFORGE5_ROOT (and optionally CREWFORGE5_HOOKS)
# through settings.json's `env` block, so neither has to be exported by hand.
#
#   env_install.sh report     [--user|--project DIR]
#   env_install.sh install    [--user|--project DIR] [--hooks] [--root DIR]
#   env_install.sh uninstall  [--user|--project DIR]
#
# WHY THIS EXISTS. Both variables were documented as shell exports the reader
# pastes, and neither can work that way:
#
#   - Shell state does not survive a Bash tool call. An `export` reaches the end
#     of its own command and no further, so every later call needs it again —
#     which is why 28 call sites across 11 files carry `${CREWFORGE5_ROOT:-.}`,
#     and that `.` silently resolves to the user's own repo once the plugin is
#     installed somewhere other than the tree it is running from.
#   - Hooks are spawned by the harness from hooks.json, not by the model. They
#     never see anything a Bash call exported, in any session, so
#     `export CREWFORGE5_HOOKS=1` in a session could not arm a hook even in
#     principle.
#
# settings.json's `env` block reaches both: it is in the environment of the Bash
# tool AND of every hook subprocess. Verified against Claude Code 2.1.246 with a
# negative control (the same hook, the same probe, `env` block removed, reads
# <UNSET>). The docs do not currently mention this, so it is asserted by
# `env_install.bats` rather than trusted to stay true.
#
# WHY THE HOOKS FLAG IS SEPARATE. `bash-guard` DENIES commands. Arming it is a
# consent decision, which is why README ships it off. `install` writes the root
# alone; `--hooks` is the only thing that writes CREWFORGE5_HOOKS=1, and the
# report says plainly which state it is in.
#
# Exits 0 on success, 1 on a refused install, 2 on usage error.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ROOT="$(cd "$HERE/.." && pwd)"

MODE="${1:-report}"
shift || true
SCOPE="user"
TARGET_DIR="$PWD"
WANT_HOOKS=0
ROOT_OVERRIDE=""

usage() {
  echo "usage: env_install.sh {report|install|uninstall} [--user|--project DIR] [--hooks] [--root DIR]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    SCOPE="user"; shift ;;
    --project) SCOPE="project"; TARGET_DIR="${2:?--project needs a directory}"; shift 2 ;;
    --hooks)   WANT_HOOKS=1; shift ;;
    --root)    ROOT_OVERRIDE="${2:?--root needs a directory}"; shift 2 ;;
    *) usage ;;
  esac
done

if [ "$SCOPE" = "user" ]; then
  SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
else
  SETTINGS="$TARGET_DIR/.claude/settings.json"
fi

# --------------------------------------------------------------------------
# Resolving the root. Most-trustworthy source first. The state file is what the
# SessionStart hook wrote this session, so it is the live install path even when
# this script is being run from a development checkout.
# --------------------------------------------------------------------------
resolve_root() {
  local state
  if [ -n "$ROOT_OVERRIDE" ]; then printf '%s\n' "$ROOT_OVERRIDE"; return 0; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then printf '%s\n' "$CLAUDE_PLUGIN_ROOT"; return 0; fi
  state="${CLAUDE_PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/crewforge5}/root"
  if [ -s "$state" ]; then
    # A stale state file pointing at a tree that no longer exists is worse than
    # no state file: it writes a confidently wrong path into settings.
    local from_state
    from_state="$(head -n1 "$state")"
    if [ -d "$from_state" ]; then printf '%s\n' "$from_state"; return 0; fi
  fi
  printf '%s\n' "$SELF_ROOT"
}

ROOT="$(resolve_root)"

# A root that does not carry this plugin's own marker is not this plugin's root.
# Writing one would break every documented command in a way that looks like the
# commands are wrong rather than the path.
root_is_sane() { [ -f "$1/.claude-plugin/plugin.json" ]; }

# --------------------------------------------------------------------------
# settings.json is the user's file and may hold anything. Every write is a merge
# through python3 (a declared base dependency), never a rewrite: the `env` block
# gains our keys and keeps every other key, and the rest of the file is
# untouched. json.dump with indent=2 matches what Claude Code writes.
# --------------------------------------------------------------------------
merge_env() { # $1 = settings path, $2 = root, $3 = write-hooks (0|1), $4 = remove (0|1)
  python3 - "$@" <<'PY'
import json, os, sys

path, root, want_hooks, remove = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"

data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        # Refuse rather than overwrite: a settings file we cannot parse is one
        # somebody hand-edited, and clobbering it loses their work silently.
        sys.exit(f"cannot parse {path}: {exc}")
    if not isinstance(data, dict):
        sys.exit(f"{path} is not a JSON object")

env = data.get("env", {})
if not isinstance(env, dict):
    sys.exit(f"{path} has an 'env' that is not an object")

before = dict(env)

if remove:
    env.pop("CREWFORGE5_ROOT", None)
    env.pop("CREWFORGE5_HOOKS", None)
else:
    env["CREWFORGE5_ROOT"] = root
    if want_hooks:
        env["CREWFORGE5_HOOKS"] = "1"

if env:
    data["env"] = env
elif "env" in data:
    # Leave no empty scaffolding behind on uninstall.
    del data["env"]

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)

for key in ("CREWFORGE5_ROOT", "CREWFORGE5_HOOKS"):
    was, now = before.get(key), env.get(key)
    if was == now:
        continue
    if now is None:
        print(f"  removed   {key}")
    elif was is None:
        print(f"  set       {key}={now}")
    else:
        print(f"  changed   {key}: {was} -> {now}")
print("  ok        %s" % path)
PY
}

read_env_key() { # $1 = settings path, $2 = key
  [ -f "$1" ] || { echo "<absent>"; return 0; }
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    print("<unparseable>"); raise SystemExit(0)
env = data.get("env") if isinstance(data, dict) else None
if not isinstance(env, dict):
    print("<absent>"); raise SystemExit(0)
print(env.get(sys.argv[2], "<absent>"))
PY
}

case "$MODE" in
  report)
    echo "settings: $SETTINGS"
    echo "resolved root: $ROOT"
    root_is_sane "$ROOT" || echo "  WARNING   no .claude-plugin/plugin.json under the resolved root"
    echo "  current   CREWFORGE5_ROOT=$(read_env_key "$SETTINGS" CREWFORGE5_ROOT)"
    echo "  current   CREWFORGE5_HOOKS=$(read_env_key "$SETTINGS" CREWFORGE5_HOOKS)"
    echo
    echo "install writes CREWFORGE5_ROOT; --hooks also arms the three opt-in hooks."
    ;;

  install)
    if ! root_is_sane "$ROOT"; then
      echo "refusing: $ROOT has no .claude-plugin/plugin.json, so it is not the plugin root." >&2
      echo "pass --root DIR if this plugin lives somewhere this script cannot infer." >&2
      exit 1
    fi
    merge_env "$SETTINGS" "$ROOT" "$WANT_HOOKS" 0 || exit 1
    if [ "$WANT_HOOKS" -ne 1 ]; then
      echo "  note      hooks left OFF; re-run with --hooks to arm bash-guard, learn-capture, learn-nudge"
    fi
    echo "  note      takes effect in the next session"
    ;;

  uninstall)
    if [ ! -f "$SETTINGS" ]; then
      echo "  nothing   $SETTINGS does not exist"
      exit 0
    fi
    merge_env "$SETTINGS" "$ROOT" 0 1 || exit 1
    ;;

  *) usage ;;
esac
