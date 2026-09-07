#!/bin/sh
# e2e gate. Runs commands.e2e, with {files} and {route} substituted when the command uses them.
# commands.e2e is null in the shipped schema, so this gate reports did_not_run until someone
# sets it. It is inert, not passing.
# A failure is still reported as fail when gates.e2e.blocking is false. The caller decides.
# Exit 78 when the gate is disabled, the command is null, the tool is missing, the command
# needs {route} and HYPERPOWER_ROUTE is unset, no files are in scope, or it times out.
set -eu

case ${1:-} in
  --help|-h)
    cat <<'EOF'
e2e.sh - hyperpower end-to-end gate

Config JSON arrives on stdin. One JSON result object goes to stdout.

  printf '%s' '{"commands":{"e2e":"pnpm playwright test"}}' | ./e2e.sh

Reads commands.e2e, gates.e2e.enabled, gates.e2e.blocking, limits.gate_timeout_seconds,
and paths.ignore. Exit 0 pass, 1 fail, 78 could not run.
EOF
    exit 0
    ;;
esac

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init e2e
hp_command_gate e2e
