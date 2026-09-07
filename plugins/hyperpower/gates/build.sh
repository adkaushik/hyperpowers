#!/bin/sh
# build gate. Runs commands.build from hyperpower.yml.
# A repo with no build step sets commands.build to null and gates.build.enabled to false.
# Exit 78 when the gate is disabled, the command is null, the tool is missing, or it times out.
set -eu

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init build
hp_command_gate build
