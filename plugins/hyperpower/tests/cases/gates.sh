#!/bin/sh
# gates/*.sh: every gate script exits 78, never 0, when it cannot run.
#
# Exit 0 from a gate means the check ran and passed. A gate whose tool is missing verified
# nothing, so it must exit 78. This case enumerates gates/ rather than naming the gates, so
# a new gate script is covered the moment it lands.
#
# Most gates run one command from hyperpower.yml, and the command key is the argument they
# pass to hp_command_gate. Those get the whole ladder: missing tool, null command, failing
# command, passing command. A gate that runs fixed tools instead gets the paths its own
# shape allows, below the loop.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'gates.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only gates'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

MISSING=hp-test-absent-tool
SCOPE=$HP_TEST_TMP/scope.txt
printf 'src/a.txt\n' > "$SCOPE"

run_gate() {
  # run_gate <script> <config file>
  T_STDIN=$2
  t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" HYPERPOWER_FILES_FILE="$SCOPE" \
    /bin/sh "$1"
}

# Reading the command key out of the script keeps this case honest when a gate changes
# which configured command it runs.
command_key() {
  sed -n 's/^hp_command_gate  *\([A-Za-z_][A-Za-z_0-9]*\).*$/\1/p' "$1" | head -n 1
}

slop_tools_installed() {
  command -v antislop >/dev/null 2>&1 || command -v ai-slop-detector >/dev/null 2>&1
}

found=0
for script in "$HP_GATES_DIR"/*.sh; do
  name=$(basename "$script" .sh)
  if [ "$name" = "_lib" ]; then continue; fi
  found=$((found + 1))
  key=$(command_key "$script")

  # 1. Disabled is a could-not-run, for every gate.
  cfg=$HP_TEST_TMP/$name-disabled.json
  printf '{"gates":{"%s":{"enabled":false,"blocking":true}},"limits":{"gate_timeout_seconds":30}}\n' \
    "$name" > "$cfg"
  run_gate "$script" "$cfg"
  t_status "gates/$name.sh exits 78 when the config disables it" 78
  t_eq "gates/$name.sh reports did_not_run when disabled" "did_not_run" \
    "$(t_json_get "$T_OUT" result)"
  t_eq "gates/$name.sh names itself in its result" "$name" "$(t_json_get "$T_OUT" gate)"

  if [ -z "$key" ]; then
    cfg=$HP_TEST_TMP/$name-bare.json
    printf '{"gates":{"%s":{"enabled":true,"blocking":true}},"limits":{"gate_timeout_seconds":30}}\n' \
      "$name" > "$cfg"

    # A gate whose tools are fixed rather than configured reaches the missing-tool path on
    # a machine that has not installed them.
    if grep -q 'command -v antislop' "$script"; then
      if slop_tools_installed; then
        t_skip "gates/$name.sh exits 78 when its tool is missing" \
          "antislop or ai-slop-detector is installed here, so the missing-tool path cannot be reached"
        continue
      fi
      run_gate "$script" "$cfg"
      t_status "gates/$name.sh exits 78 when its tool is missing" 78
      t_eq "gates/$name.sh reports did_not_run for a missing tool" "did_not_run" \
        "$(t_json_get "$T_OUT" result)"
      t_file_has "gates/$name.sh names the tool that is not on PATH" "$T_OUT" "not on PATH"
      continue
    fi

    run_gate "$script" "$cfg"
    t_status "gates/$name.sh exits 78 when nothing it needs is configured" 78
    t_eq "gates/$name.sh reports did_not_run when nothing is configured" "did_not_run" \
      "$(t_json_get "$T_OUT" result)"
    continue
  fi

  # 2. The configured command names a tool that is not installed.
  cfg=$HP_TEST_TMP/$name-missing.json
  printf '{"gates":{"%s":{"enabled":true,"blocking":true}},"commands":{"%s":"%s --check"},"limits":{"gate_timeout_seconds":30}}\n' \
    "$name" "$key" "$MISSING" > "$cfg"
  run_gate "$script" "$cfg"
  t_status "gates/$name.sh exits 78 when its tool is missing" 78
  t_eq "gates/$name.sh reports did_not_run for a missing tool" "did_not_run" \
    "$(t_json_get "$T_OUT" result)"
  t_file_has "gates/$name.sh names the tool that is not on PATH" "$T_OUT" "$MISSING"

  # 3. The command is null, which is how a repo turns a check off.
  cfg=$HP_TEST_TMP/$name-null.json
  printf '{"gates":{"%s":{"enabled":true,"blocking":true}},"commands":{"%s":null},"limits":{"gate_timeout_seconds":30}}\n' \
    "$name" "$key" > "$cfg"
  run_gate "$script" "$cfg"
  t_status "gates/$name.sh exits 78 when its command is null" 78
  t_file_has "gates/$name.sh names the command it needed" "$T_OUT" "commands.$key"

  # 4. A command that runs and fails is a failure, not a could-not-run.
  cfg=$HP_TEST_TMP/$name-fail.json
  printf '{"gates":{"%s":{"enabled":true,"blocking":true}},"commands":{"%s":"false"},"limits":{"gate_timeout_seconds":30}}\n' \
    "$name" "$key" > "$cfg"
  run_gate "$script" "$cfg"
  t_status "gates/$name.sh exits 1 when its command fails" 1
  t_eq "gates/$name.sh reports fail when its command fails" "fail" \
    "$(t_json_get "$T_OUT" result)"

  # 5. A command that runs and passes is the only way to exit 0.
  cfg=$HP_TEST_TMP/$name-pass.json
  printf '{"gates":{"%s":{"enabled":true,"blocking":true}},"commands":{"%s":"true"},"limits":{"gate_timeout_seconds":30}}\n' \
    "$name" "$key" > "$cfg"
  run_gate "$script" "$cfg"
  t_status "gates/$name.sh exits 0 when its command passes" 0
  t_eq "gates/$name.sh reports pass when its command passes" "pass" \
    "$(t_json_get "$T_OUT" result)"
done

t_ge "gates/ ships gate scripts to check" 5 "$found"

# ---------------------------------------------------------------------------
# The browser gate needs a headless browser it cannot configure. Point it at one that is
# not there and it must report that, before it boots anything.

BROWSER=$HP_GATES_DIR/browser.sh
if [ -f "$BROWSER" ]; then
  cfg=$HP_TEST_TMP/browser-no-binary.json
  printf '{"gates":{"browser":{"enabled":true,"blocking":true}},' > "$cfg"
  printf '"commands":{"dev_server":"true","dev_url":"http://127.0.0.1:1"},' >> "$cfg"
  printf '"limits":{"gate_timeout_seconds":30}}\n' >> "$cfg"
  T_STDIN=$cfg
  t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" \
    HYPERPOWER_BROWSER_BIN="$HP_TEST_TMP/no-such-browser" /bin/sh "$BROWSER"
  t_status "gates/browser.sh exits 78 when its browser is missing" 78
  t_eq "gates/browser.sh reports did_not_run for a missing browser" "did_not_run" \
    "$(t_json_get "$T_OUT" result)"
fi

# ---------------------------------------------------------------------------
# Empty config on stdin is what hp-selfcheck probes each gate with. Still a could-not-run.

printf '' > "$HP_TEST_TMP/empty.json"
for script in "$HP_GATES_DIR"/*.sh; do
  name=$(basename "$script" .sh)
  if [ "$name" = "_lib" ]; then continue; fi
  if grep -q 'command -v antislop' "$script" && slop_tools_installed; then
    t_skip "gates/$name.sh exits 78 on an empty config" \
      "its tools are installed here, so an empty config would run them"
    continue
  fi
  run_gate "$script" "$HP_TEST_TMP/empty.json"
  t_status "gates/$name.sh exits 78 on an empty config" 78
done
