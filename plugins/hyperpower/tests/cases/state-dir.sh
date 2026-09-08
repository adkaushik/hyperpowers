#!/bin/sh
# paths.state moves everything the harness writes. The default must not change, an
# override must be honoured by every writer, and a relative value must anchor to the repo
# root rather than the working directory.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'state-dir.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only state-dir'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

MOVED="$HP_TEST_TMP/moved-repo"
mkdir -p "$MOVED"
( cd "$MOVED" && git init -q && git commit -q --allow-empty -m init ) >/dev/null 2>&1

write_config() {
  cat > "$MOVED/hyperpower.yml" <<YML
version: 1
project: { name: moved, type: cli, languages: [go], package_manager: go }
paths: { source: [src/], tests: [t/], ignore: []${1:-} }
commands: { typecheck: "true", test_scoped: null, lint: null, build: null, install: null, test: null, dev_server: null, dev_url: null, e2e: null }
gates:
  types: { enabled: true, blocking: true }
  unit: { enabled: false }
  lint: { enabled: false }
  build: { enabled: false }
  slop: { enabled: false }
  browser: { enabled: false }
  a11y: { enabled: false }
  visual: { enabled: false }
  e2e: { enabled: false }
models: { judgment: claude-opus-5, mechanical: claude-haiku-4-5 }
limits: { rulebook_max_rules: 30, fix_loop_max_rounds: 5, scout_max_new_per_run: 3, janitor_max_new_per_run: 5, gate_timeout_seconds: 60 }
memory: { decisions_dir: decisions/, archivist: true, promoter: true }
telemetry: { enabled: true, destination: local, redact_paths: true }
voice: { adhd_shaping: true, plain_english: true }
YML
}

# ---------------------------------------------------------------------------
# 1. The default is .hyperpower, and it must stay that way. Changing it silently
#    orphans every run already recorded in every repo.

write_config ""
t_hp_config --root "$MOVED" --state-dir
t_status "hp-config --state-dir exits 0" 0
t_eq "the default state directory is .hyperpower" "$MOVED/.hyperpower" "$(t_out)"

# ---------------------------------------------------------------------------
# 2. paths.state moves it, and the value is anchored to the repo root.

write_config ", state: .claude/hyperpower"
t_hp_config --root "$MOVED" --state-dir
t_eq "paths.state moves the state directory" "$MOVED/.claude/hyperpower" "$(t_out)"

T_CWD=$HP_TEST_TMP
t_hp_config --root "$MOVED" --state-dir
t_eq "a relative paths.state anchors to the repo root, not the cwd" \
  "$MOVED/.claude/hyperpower" "$(t_out)"

# ---------------------------------------------------------------------------
# 3. HYPERPOWER_STATE_DIR wins. hp-gates pins one value for every gate it spawns,
#    so the variable has to beat the file.

t_run env HYPERPOWER_STATE_DIR=.elsewhere "$HP_PYTHON" "$HP_CONFIG" --root "$MOVED" --state-dir
t_eq "HYPERPOWER_STATE_DIR beats paths.state" "$MOVED/.elsewhere" "$(t_out)"

# ---------------------------------------------------------------------------
# 4. The writers honour it. A run recorded under an override must leave nothing
#    at the default path — a stray tree is invisible to /hyperpower:why.

t_run env HYPERPOWER_REPO_ROOT="$MOVED" "$HP_PYTHON" "$HP_JOURNAL" new --task-class feature
t_status "hp-journal new exits 0 under an override" 0
MRUN=$(t_out)

t_dir "the run folder is under the configured directory" \
  "$MOVED/.claude/hyperpower/runs/$MRUN"
t_no_file "nothing is written at the default path" "$MOVED/.hyperpower"

t_run env HYPERPOWER_REPO_ROOT="$MOVED" "$HP_PYTHON" "$HP_GATES_BIN" --run "$MRUN"
t_status "hp-gates exits 0 with every enabled blocking gate passing" 0
t_file "hp-gates records gates.json under the configured directory" \
  "$MOVED/.claude/hyperpower/runs/$MRUN/gates.json"
t_no_file "hp-gates leaves no stray tree at the default path" "$MOVED/.hyperpower"
