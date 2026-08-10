#!/usr/bin/env bash
# bats-fallback.sh — minimal bats-compat shim for plain-bash invocation.
#
# Under real `bats`, sourcing this file is additive: it defines `assert_*` /
# `refute_*` helpers that mirror the bats-assert API but use plain shell
# tests so they work even when bats-assert isn't installed.
#
# Under plain `bash <file.bats>` (no real bats on PATH), this file detects
# the missing BATS_VERSION env var, preprocesses the calling .bats file
# into a runnable bash script (transforms `@test "..." { ... }` blocks into
# functions, then invokes each through setup/teardown), and re-execs the
# result. The original file is untouched.
#
# Every .bats fixture in scripts/tests/ sources this file at the top via
#   source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"
# which works under both modes.

# ---------------------------------------------------------------------------
# Plain-bash fallback: preprocess the calling file and re-exec.
# ---------------------------------------------------------------------------
# Detect: we're being sourced from a .bats file under plain `bash`, not under
# real bats (BATS_VERSION unset), and haven't already preprocessed (guard).
if [ -z "${BATS_VERSION:-}" ] && [ -z "${_BATS_FALLBACK_ACTIVE:-}" ]; then
  _bats_fb_caller="${BASH_SOURCE[1]:-}"
  # Only engage fallback when sourced from a .bats file (avoid running when
  # this lib is sourced standalone for e.g. ad-hoc shell experiments).
  case "$_bats_fb_caller" in
    *.bats)
      export _BATS_FALLBACK_ACTIVE=1
      _bats_fb_tmp="$(mktemp -t bats-fb.XXXXXX)"
      # Preprocess: strip the source-line for this lib (we inline its
      # definitions instead), transform @test headers into function defs,
      # and append a runner at the end of file.
      awk -v lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bats-fallback.sh" '
        BEGIN { n = 0 }
        # Drop the shebang line; we re-add our own header below.
        NR == 1 && /^#!/ { next }
        # Drop the source-line for bats-fallback.sh (any path form).
        /^[[:space:]]*source[[:space:]].*bats-fallback\.sh/ { next }
        # Transform: @test "NAME" {  ->  __bats_test_N() { __bats_name="NAME"
        /^@test[[:space:]]/ {
          line = $0
          sub(/^@test[[:space:]]+/, "", line)
          sub(/[[:space:]]*\{[[:space:]]*$/, "", line)
          # Strip wrapping double-quotes from name (best-effort).
          name = line
          sub(/^"/, "", name); sub(/"$/, "", name)
          n++
          names[n] = name
          printf("__bats_test_%d() {\n", n)
          next
        }
        { print }
        END {
          print ""
          print "# --- bats-fallback runner ---------------------------------"
          print "__bats_fb_failed=0"
          print "__bats_fb_pass=0"
          print "__bats_fb_fail=0"
          for (i = 1; i <= n; i++) {
            # Names containing a literal single-quote are out of scope; the
            # existing fixtures use plain ASCII identifiers in test names.
            nm = names[i]
            printf("__bats_fb_run_one \"%s\" __bats_test_%d || __bats_fb_failed=1\n", nm, i)
          }
          print "__bats_fb_summary"
          print "exit \"$__bats_fb_failed\""
        }
      ' "$_bats_fb_caller" > "$_bats_fb_tmp"

      # Header for the rewritten file: re-source this lib (now with
      # _BATS_FALLBACK_ACTIVE=1 so we skip the preprocess branch and define
      # only the runtime helpers), set bats-compat globals, then run.
      _bats_fb_final="$(mktemp -t bats-fb-final.XXXXXX)"
      {
        printf '#!/usr/bin/env bash\n'
        printf 'set -uo pipefail\n'
        printf 'export BATS_TEST_FILENAME=%q\n' "$_bats_fb_caller"
        printf 'export BATS_TEST_DIRNAME=%q\n' "$(cd "$(dirname "$_bats_fb_caller")" && pwd)"
        printf 'source %q\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bats-fallback.sh"
        cat "$_bats_fb_tmp"
      } > "$_bats_fb_final"

      rm -f "$_bats_fb_tmp"
      # Replace the current process with the rewritten script.
      trap 'rm -f "$_bats_fb_final"' EXIT
      # Note: exec replaces process, so the trap above only fires if exec fails.
      exec bash "$_bats_fb_final"
      # If exec returns (it shouldn't), fail loud.
      echo "bats-fallback: exec of preprocessed file failed" >&2
      exit 127
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Runtime helpers (used under both real bats and fallback re-exec).
# ---------------------------------------------------------------------------
# Under real bats these names shadow nothing the existing fixtures rely on
# (the fixtures use plain `[ ]` / `[[ ]]` everywhere); under fallback, they
# back the assert API requested by mech-8's deliverable list.

# `run`: capture command status + stdout/stderr (merged) into $status/$output.
# Bats provides this natively; we only define it when running under fallback.
if [ -n "${_BATS_FALLBACK_ACTIVE:-}" ] && ! declare -F run >/dev/null 2>&1; then
  run() {
    # Mirror bats: $status = exit code, $output = combined stdout+stderr,
    # $lines = $output split by newline. Errexit must NOT propagate from
    # the invoked command.
    local _rc=0
    local _out
    set +e
    _out="$("$@" 2>&1)"
    _rc=$?
    set -e 2>/dev/null || true
    status=$_rc
    output=$_out
    # shellcheck disable=SC2034  # lines is consumed by callers via $lines[@]
    mapfile -t lines <<< "$_out" 2>/dev/null || lines=("$_out")
    return 0
  }
fi

# --- assertion helpers ------------------------------------------------------
# Under real bats, bats-assert (when installed) provides the same names with
# nicer diagnostics; if bats-assert isn't loaded, ours work as a fallback.
# We never overwrite an existing definition.

_bats_fb_fail() {
  printf 'assertion failed: %s\n' "$*" >&2
  return 1
}

if ! declare -F assert_equal >/dev/null 2>&1; then
  assert_equal() {
    local expected="${1-}" actual="${2-}"
    if [ "$expected" != "$actual" ]; then
      _bats_fb_fail "expected '$expected', got '$actual'"
    fi
  }
fi

if ! declare -F assert_not_equal >/dev/null 2>&1; then
  assert_not_equal() {
    local a="${1-}" b="${2-}"
    if [ "$a" = "$b" ]; then
      _bats_fb_fail "expected '$a' != '$b'"
    fi
  }
fi

if ! declare -F assert_success >/dev/null 2>&1; then
  assert_success() {
    if [ "${status:-1}" -ne 0 ]; then
      _bats_fb_fail "expected success, got status=$status; output: ${output:-}"
    fi
  }
fi

if ! declare -F assert_failure >/dev/null 2>&1; then
  assert_failure() {
    if [ "${status:-0}" -eq 0 ]; then
      _bats_fb_fail "expected failure, got status=0; output: ${output:-}"
    fi
  }
fi

if ! declare -F assert_output >/dev/null 2>&1; then
  assert_output() {
    local expected="${1-}"
    if [ "${output-}" != "$expected" ]; then
      _bats_fb_fail "output mismatch; expected '$expected', got '${output-}'"
    fi
  }
fi

if ! declare -F assert_stderr >/dev/null 2>&1; then
  # bats merges stderr into $output by default; we treat assert_stderr as a
  # substring check against $output (best-effort under the merged model).
  assert_stderr() {
    local expected="${1-}"
    case "${output-}" in
      *"$expected"*) : ;;
      *) _bats_fb_fail "stderr missing expected '$expected'; got '${output-}'" ;;
    esac
  }
fi

if ! declare -F refute_output >/dev/null 2>&1; then
  refute_output() {
    local disallowed="${1-}"
    case "${output-}" in
      *"$disallowed"*) _bats_fb_fail "output contains disallowed '$disallowed'" ;;
    esac
  }
fi

if ! declare -F refute_stderr >/dev/null 2>&1; then
  refute_stderr() {
    local disallowed="${1-}"
    case "${output-}" in
      *"$disallowed"*) _bats_fb_fail "stderr contains disallowed '$disallowed'" ;;
    esac
  }
fi

if ! declare -F assert_line >/dev/null 2>&1; then
  assert_line() {
    local needle="${1-}"
    case "${output-}" in
      *"$needle"*) : ;;
      *) _bats_fb_fail "no line containing '$needle' in output: ${output-}" ;;
    esac
  }
fi

if ! declare -F refute_line >/dev/null 2>&1; then
  refute_line() {
    local needle="${1-}"
    case "${output-}" in
      *"$needle"*) _bats_fb_fail "line containing '$needle' found in output" ;;
    esac
  }
fi

if ! declare -F assert_regex >/dev/null 2>&1; then
  assert_regex() {
    local actual="${1-}" pattern="${2-}"
    if ! [[ "$actual" =~ $pattern ]]; then
      _bats_fb_fail "'$actual' does not match regex '$pattern'"
    fi
  }
fi

# ---------------------------------------------------------------------------
# Fallback test runner internals (only used under _BATS_FALLBACK_ACTIVE).
# ---------------------------------------------------------------------------
if [ -n "${_BATS_FALLBACK_ACTIVE:-}" ]; then
  __bats_fb_run_one() {
    local name="$1" fn="$2"
    local rc=0
    # Reset bats-compat globals between tests.
    status=0
    output=""
    # Run setup → test → teardown in a subshell so per-test env / cd are
    # isolated, matching bats semantics.
    (
      set +e
      if declare -F setup >/dev/null 2>&1; then setup; fi
      "$fn"
      _trc=$?
      if declare -F teardown >/dev/null 2>&1; then teardown; fi
      exit "$_trc"
    )
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '  ok %s\n' "$name"
      __bats_fb_pass=$((__bats_fb_pass + 1))
      return 0
    else
      printf '  not ok %s (rc=%d)\n' "$name" "$rc" >&2
      __bats_fb_fail=$((__bats_fb_fail + 1))
      return 1
    fi
  }

  __bats_fb_summary() {
    local total=$((__bats_fb_pass + __bats_fb_fail))
    printf '%s: %d/%d passed\n' "${BATS_TEST_FILENAME##*/}" "$__bats_fb_pass" "$total" >&2
  }
fi
