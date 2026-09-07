#!/bin/sh
# types gate. Runs commands.typecheck from hyperpower.yml.
# Exit 78 when the gate is disabled, the command is null, the tool is missing, or it times out.
set -eu

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init types
hp_command_gate typecheck
