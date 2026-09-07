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
