#!/bin/sh
# hp-config: the documented config parses, a missing config stops the harness, local
# overrides merge per field, and the repo root comes from HYPERPOWER_REPO_ROOT.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-config.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-config'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

BLOCKS=$HP_TEST_TMP/blocks
BLOCK_ROOT=$HP_TEST_TMP/block-root
NO_CONFIG=$HP_TEST_TMP/no-config
OTHER_ROOT=$HP_TEST_TMP/other-root
mkdir -p "$BLOCKS" "$BLOCK_ROOT" "$NO_CONFIG" "$OTHER_ROOT"

# ---------------------------------------------------------------------------
# 1. Every yaml block in docs/configuration.md parses.
#
# The blocks are read out of the document at test time. A field added to the document and
# not to the parser fails here, which is the drift this test exists to catch.

count=$(t_tool yaml-blocks "$HP_DOCS/configuration.md" "$BLOCKS")
t_ge "docs/configuration.md still ships its four yaml blocks" 4 "$count"

index=0
for block in "$BLOCKS"/*.yml; do
  index=$((index + 1))
  cp "$block" "$BLOCK_ROOT/hyperpower.yml"
  t_hp_config --root "$BLOCK_ROOT" --source
  t_status "yaml block $index of docs/configuration.md parses" 0
  t_eq "yaml block $index uses no key outside the schema" "[]" \
    "$(t_json_get "$T_OUT" unknown_keys)"
  t_eq "yaml block $index uses no value of the wrong type" "[]" \
    "$(t_json_get "$T_OUT" type_errors)"
done

# The first block is the full schema. Every documented section must survive the merge.
cp "$BLOCKS/01.yml" "$BLOCK_ROOT/hyperpower.yml"
t_hp_config --root "$BLOCK_ROOT" --json
t_status "the full schema block prints an effective config" 0
for section in project paths commands gates models limits memory telemetry voice; do
  t_ne "the full schema block keeps the $section section" "<missing>" \
    "$(t_json_get "$T_OUT" "$section")"
done
t_eq "the full schema block keeps a nested gate field" "core" \
  "$(t_json_get "$T_OUT" gates.slop.profile)"
t_eq "the full schema block keeps a null command" "null" \
  "$(t_json_get "$T_OUT" commands.e2e)"

# ---------------------------------------------------------------------------
# 2. No hyperpower.yml is exit 78, and the message names the command that writes one.

t_hp_config --root "$NO_CONFIG"
t_status "hp-config with no hyperpower.yml exits 78" 78
t_stderr_has "the message names /hyperpower:init" "/hyperpower:init"
t_stderr_has "the message says the harness does not guess" "does not guess"

T_CWD=$NO_CONFIG
t_hp_config
t_status "hp-config exits 78 in a directory with no config above it" 78

# ---------------------------------------------------------------------------
# 3. HYPERPOWER_REPO_ROOT names the root.

cat > "$OTHER_ROOT/hyperpower.yml" <<'EOF'
version: 1
project:
  name: other-root
  type: library
EOF

t_run env HYPERPOWER_REPO_ROOT="$OTHER_ROOT" "$HP_PYTHON" "$HP_CONFIG" --json
t_status "HYPERPOWER_REPO_ROOT resolves a root outside the working directory" 0
t_eq "HYPERPOWER_REPO_ROOT wins over the working directory" "other-root" \
  "$(t_json_get "$T_OUT" project.name)"

t_hp_config --json
t_status "without the variable the working directory resolves the root" 0
t_eq "the scratch repo is the root when nothing overrides it" "scratch" \
  "$(t_json_get "$T_OUT" project.name)"

t_run env HYPERPOWER_REPO_ROOT="$OTHER_ROOT" "$HP_PYTHON" "$HP_CONFIG" \
  --root "$HP_TEST_REPO" --json
t_eq "--root wins over HYPERPOWER_REPO_ROOT" "scratch" "$(t_json_get "$T_OUT" project.name)"

t_run env HYPERPOWER_REPO_ROOT="$OTHER_ROOT/hyperpower.yml" "$HP_PYTHON" "$HP_CONFIG" --json
t_status "HYPERPOWER_REPO_ROOT pointing at a file is bad input, not a missing config" 1

# ---------------------------------------------------------------------------
# 4. hyperpower.local.yml overrides field by field, and the hash moves with it.

t_hp_config --root "$HP_TEST_REPO" --hash
t_status "hp-config --hash prints a hash" 0
before=$(t_out)
t_file_has "the hash is a sha256" "$T_OUT" "sha256:"

cat > "$HP_TEST_REPO/hyperpower.local.yml" <<'EOF'
project:
  name: local-name
EOF

t_hp_config --root "$HP_TEST_REPO" --source
t_status "hp-config reads hyperpower.local.yml" 0
t_eq "the local file overrides the field it names" "local-name" \
  "$(t_json_get "$T_OUT" config.project.name)"
t_eq "the committed value survives for a field the local file leaves alone" "cli" \
  "$(t_json_get "$T_OUT" config.project.type)"
t_eq "the overridden field is sourced to the local file" "hyperpower.local.yml" \
  "$(t_json_get "$T_OUT" 'sources.project.name')"
t_eq "the untouched field stays sourced to the committed file" "hyperpower.yml" \
  "$(t_json_get "$T_OUT" 'sources.project.type')"

t_hp_config --root "$HP_TEST_REPO" --hash
after=$(t_out)
t_ne "the config hash moves when the effective config moves" "$before" "$after"

rm -f "$HP_TEST_REPO/hyperpower.local.yml"
t_hp_config --root "$HP_TEST_REPO" --hash
t_eq "removing the local file restores the committed hash" "$before" "$(t_out)"

# ---------------------------------------------------------------------------
# 5. A file that does not parse is exit 1, named with its line.

BROKEN=$HP_TEST_TMP/broken
mkdir -p "$BROKEN"
printf 'version: 1\nproject:\n\tname: tabbed\n' > "$BROKEN/hyperpower.yml"
t_hp_config --root "$BROKEN"
t_status "a tab in indentation is exit 1, not exit 78" 1
t_stderr_has "the parse error names the line" "hyperpower.yml:3"
t_stderr_has "the parse error says what to use instead" "Use spaces"
