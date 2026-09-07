#!/bin/sh
# lint gate. Runs commands.lint, with {files} substituted when the command uses it.
# A failure is still reported as fail when gates.lint.blocking is false. The caller decides.
# Exit 78 when the gate is disabled, the command is null, the tool is missing, no files are in
# scope, or it times out.
set -eu

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init lint
hp_command_gate lint
