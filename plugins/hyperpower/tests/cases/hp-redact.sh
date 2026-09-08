#!/bin/sh
# hp-redact: it removes real paths from an aggregate, and it leaves the fields the
# aggregate is grouped by alone. A redactor that eats gate names or model ids destroys the
# analysis it exists to protect.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-redact.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-redact'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

HP_REDACT="$HP_SCRIPTS/hp-redact"

# t_run forces stdin from a file, so every record goes through one.
t_redact() {
  in=$1; shift
  T_STDIN=$in
  t_run "$HP_PYTHON" "$HP_REDACT" "$@"
}

t_file "hp-redact exists" "$HP_REDACT"

REC="$HP_TEST_TMP/rec.jsonl"
cat > "$REC" <<'JSON'
{"ts":"2026-09-08T00:00:00Z","stage":"gate:types","model":"claude-opus-5","outcome":"src/api/settings.ts:42 failed","sha":"a3f19c2"}
JSON

# ---------------------------------------------------------------------------
# 1. A path is removed. This is the whole job.

t_redact "$REC" --stdin
t_status "hp-redact --stdin exits 0" 0
t_file_lacks "the real path is gone" "$T_OUT" "src/api/settings.ts"

# ---------------------------------------------------------------------------
# 2. The fields an aggregate groups by survive. Redaction must not destroy the analysis.

t_stdout_has "the gate name survives" "gate:types"
t_stdout_has "the model id survives" "claude-opus-5"
t_stdout_has "the git sha survives" "a3f19c2"
t_stdout_has "the timestamp survives" "2026-09-08"

# ---------------------------------------------------------------------------
# 3. The same path yields the same token, so an aggregate can still group by file.
#    An unstable token leaves the output readable and the analysis worthless.

cp "$T_OUT" "$HP_TEST_TMP/first.json"
t_redact "$REC" --stdin
if cmp -s "$HP_TEST_TMP/first.json" "$T_OUT"; then
  t_ok "the same path redacts to the same token twice"
else
  t_bad "the same path redacts to the same token twice" \
    "two runs of the same record produced different output"
fi

# ---------------------------------------------------------------------------
# 4. Two different paths do not collide onto one token.

TWO="$HP_TEST_TMP/two.jsonl"
printf '{"a":"src/one.ts"}\n{"a":"src/two.ts"}\n' > "$TWO"
t_redact "$TWO" --stdin
t_status "two records redact without error" 0
if [ "$(sort -u "$T_OUT" | wc -l | tr -d ' ')" = "2" ]; then
  t_ok "two different paths give two different tokens"
else
  t_bad "two different paths give two different tokens" "both records collapsed to one line"
fi

# ---------------------------------------------------------------------------
# 5. A salt path that is not a regular file fails with a cause, not a stack trace.
#    This recursed until RecursionError before it was fixed.

mkdir -p "$HP_TEST_TMP/saltdir"
t_redact "$REC" --stdin --salt-file "$HP_TEST_TMP/saltdir"
t_file_lacks "a directory salt path does not print a traceback" "$T_ERR" "RecursionError"
t_file_lacks "a directory salt path emits no redacted output" "$T_OUT" "src/api"
