#!/bin/sh
# unit gate. Runs commands.test_scoped with {files} substituted.
# It never falls back to commands.test. A scoped gate does not silently run the whole suite.
# Exit 78 when the gate is disabled, the command is null, the tool is missing, no files are in
# scope, or it times out.
set -eu

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init unit
hp_command_gate test_scoped
