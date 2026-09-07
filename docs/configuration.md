# Configuration

## Files and precedence

| File | Committed | Purpose |
|---|---|---|
| `hyperpower.yml` | yes | The repo's config. Shared with the team. |
| `hyperpower.local.yml` | no, gitignored | Your machine. Overrides the above, field by field. |

Local overrides merge per field, not per section. Setting `models.judgment` locally leaves
`models.mechanical` as the committed value.

Check what is actually in effect:

```
/hyperpower:config
```

It prints each field and which file it came from.

## What reads these files

One thing does: `plugins/hyperpower/scripts/hp-config`. Every skill, agent, and gate reads
the config through it and never parses the YAML itself, so a run, `/hyperpower:config`, and
`/hyperpower:doctor` all see the same values.

```sh
hp-config              # the effective config, indented
hp-config --json       # the same, on one line
hp-config --source     # config, sources, overrides, unknown_keys, type_errors, hash
hp-config --hash       # the config hash alone
```

Exit 0 printed, 1 a file did not parse, 78 no `hyperpower.yml`. There is no fourth outcome:
with no config the harness stops and says so rather than guessing one.

`--source` maps every dotted leaf path to `hyperpower.yml`, `hyperpower.local.yml`, or
`default`. A list is one leaf, so a local `paths.source` replaces the committed list whole
and is labelled `hyperpower.local.yml` entirely. It does not concatenate.

### The config hash

`hp-config --hash` prints a sha256 over the effective config. `hp-journal new` records it
in the run's `meta.json`, and `/hyperpower:resume` compares it before replaying: a hash
that no longer matches means the gate commands may have changed, so every step is treated
as drifted. Editing `hyperpower.yml` mid-run is visible rather than silent.

### Unknown keys and wrong types

A key not in the schema below is never merged and never dropped silently. It lands in
`unknown_keys` with the file and value it came from, and `/hyperpower:config` prints it
under `Not in schema`.

A value whose type disagrees with the schema lands in `type_errors` and is still used, with
one exception: a map replaced by a scalar keeps the defaults, because the section's other
fields would otherwise vanish.

### The YAML subset

`hp-config` is standard library only, so it parses a deliberate subset: nested maps, block
lists of scalars, inline maps, inline lists, quoted and unquoted scalars, `null`, booleans,
integers, floats, and `#` comments.

It rejects anchors, aliases, tags, block scalars, lists of maps, multiple documents,
duplicate keys, and tabs in indentation, naming the file and the line. Write plain YAML and
none of this comes up. Every example on this page parses.

## Writing it by hand

You do not have to run the interview. Write the file yourself and `init` will read it,
fill only the gaps, and verify.

## Full schema

```yaml
version: 1

project:
  name: acme-web
  type: web-frontend          # web-frontend | backend | monorepo | library | cli | mobile | other
  languages: [typescript, css]
  package_manager: pnpm

paths:
  source: [src/]              # the harness may edit these
  tests: [src/**/*.test.ts]
  docs: [docs/]
  ignore: [dist/, node_modules/, generated/]

commands:
  install: pnpm install --frozen-lockfile
  typecheck: tsc --noEmit
  test: pnpm vitest run
  test_scoped: pnpm vitest run {files}
  lint: pnpm eslint {files}
  build: pnpm build
  dev_server: pnpm dev
  dev_url: http://localhost:5173
  e2e: null

gates:
  types:   { enabled: true,  blocking: true }
  unit:    { enabled: true,  blocking: true }
  lint:    { enabled: true,  blocking: false }
  build:   { enabled: true,  blocking: true }
  slop:    { enabled: true,  blocking: true,  profile: core }
  e2e:     { enabled: false, blocking: false, reason: "no e2e command configured" }
  browser: { enabled: false, blocking: false, reason: "no dev_url configured" }
  a11y:    { enabled: false, blocking: false }
  visual:  { enabled: false, blocking: false }

models:
  judgment: claude-opus-5
  mechanical: claude-haiku-4-5

limits:
  rulebook_max_rules: 30
  fix_loop_max_rounds: 5
  scout_max_new_per_run: 3
  janitor_max_new_per_run: 5
  gate_timeout_seconds: 600

memory:
  decisions_dir: decisions/
  archivist: true
  promoter: true

telemetry:
  enabled: true
  destination: local          # local only. no remote destination exists.
  redact_paths: true

voice:
  adhd_shaping: true
  plain_english: true
```

## Field notes

### paths.source

The only directories the harness may edit. Everything else is read-only to it. Keep this
tight.

### commands

Two template variables, and only these two:

| Variable | Becomes |
|---|---|
| `{files}` | the scoped file list for this run |
| `{route}` | the changed route, for browser and a11y gates |

A command set to `null` disables its gate.

### gates

| Field | Meaning |
|---|---|
| `enabled` | whether it runs at all |
| `blocking` | `true` stops the run on failure, `false` reports a warning |
| `reason` | written by `init` or `doctor` when it disables a gate |

Start with `lint` non-blocking. Promote it once the codebase is clean.

### models

`mechanical` runs assumption checking, archiving, promoting, scouting, janitoring, and
diff partitioning. Use a cheap model. It is most of the call volume.

`judgment` runs planning, review adjudication, and design. Use your best model.

### limits.rulebook_max_rules

The rulebook loads on every run, so its size is a tax on every run. At the cap, adding a
rule evicts the weakest one.

Raising this is the most common way to make the harness slowly worse. Raise it only when
you have checked `/hyperpower:rules --unused` and found nothing to drop.

### telemetry

`destination` accepts one value: `local`. There is no remote option. See
[analytics.md](analytics.md).

## Examples

### Node monorepo

```yaml
project: { type: monorepo, package_manager: pnpm }
paths:
  source: [packages/*/src/]
  ignore: [packages/*/dist/, node_modules/]
commands:
  typecheck: pnpm -r exec tsc --noEmit
  test_scoped: pnpm vitest run {files}
  build: pnpm -r build
```

### Python service

```yaml
project: { type: backend, package_manager: uv, languages: [python] }
paths:
  source: [app/]
  tests: [tests/]
commands:
  install: uv sync --frozen
  typecheck: uv run mypy app
  test_scoped: uv run pytest {files}
  lint: uv run ruff check {files}
  build: null
gates:
  build: { enabled: false, reason: "no build step" }
  browser: { enabled: false }
  a11y: { enabled: false }
  visual: { enabled: false }
```

### Go CLI

```yaml
project: { type: cli, package_manager: go, languages: [go] }
paths: { source: [cmd/, internal/] }
commands:
  typecheck: go vet ./...
  test_scoped: go test ./...
  build: go build ./...
  lint: golangci-lint run
```
