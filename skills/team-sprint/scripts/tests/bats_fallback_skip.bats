#!/usr/bin/env bats
# bats_fallback_skip.bats — pins the `skip` contract for the fallback runner.
#
# Under real bats, `skip "reason"` halts the test body: no statement after it
# may execute. The plain-bash fallback runner (lib/bats-fallback.sh) must
# honour the same contract, otherwise a guard like
#   [ -f "$peer" ] || skip "peer not installed"
# silently keeps executing under `bash <file.bats>` and asserts against a
# missing fixture. This suite generates a tiny inner .bats whose test body is
# `skip` followed by a sentinel write, runs it under both runners with the
# outer runner's env scrubbed, and asserts the sentinel never appears.
#
# NOTE: the inner fixture is generated with printf, not a heredoc. The
# fallback preprocessor awk-scans the whole outer file, so a literal
# `@test ... {` or `source ...bats-fallback.sh` line at column 0 — even
# inside a quoted heredoc — would be transformed/dropped when THIS file runs
# under plain bash. Single-quoted printf keeps $SENTINEL literal in the
# inner file, matching the quoted-heredoc guarantee.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  LIB="$(cd "$BATS_TEST_DIRNAME/lib" && pwd)/bats-fallback.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

_write_inner() {
  inner="$TMP/inner_skip.bats"
  {
    printf '#!/usr/bin/env bats\n'
    printf 'source %q\n' "$LIB"
    printf '\n'
    printf '@test "inner: statement after skip must not run" {\n'
    printf '  skip "pin"\n'
    printf '  echo leaked > "$SENTINEL"\n'
    printf '}\n'
  } > "$inner"
}

@test "skip halts the test body under both the fallback runner and real bats" {
  _write_inner

  # Leg A — plain-bash fallback runner. Scrub the outer runner's markers so
  # the inner file preprocesses itself from scratch.
  run env -u BATS_VERSION -u _BATS_FALLBACK_ACTIVE \
      -u BATS_TEST_FILENAME -u BATS_TEST_DIRNAME \
      SENTINEL="$TMP/leak-fb" bash "$inner"
  assert_success
  if [ -e "$TMP/leak-fb" ]; then
    echo "leg A (fallback runner): statement after skip executed — sentinel $TMP/leak-fb exists" >&2
    return 1
  fi

  # Leg B — real bats, when installed (native skip; contract reference).
  if command -v bats >/dev/null 2>&1; then
    run env -u BATS_VERSION -u _BATS_FALLBACK_ACTIVE \
        -u BATS_TEST_FILENAME -u BATS_TEST_DIRNAME \
        SENTINEL="$TMP/leak-bats" bats "$inner"
    assert_success
    if [ -e "$TMP/leak-bats" ]; then
      echo "leg B (real bats): statement after skip executed — sentinel $TMP/leak-bats exists" >&2
      return 1
    fi
  fi
}
