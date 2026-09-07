---
name: config
description: Print the effective hyperpower config field by field, with the file each value came from. Shows how hyperpower.local.yml overrides hyperpower.yml per field, and which fields are still at their built-in default. Read only. Use /hyperpower:config.
---

# Config

Print the effective config, one leaf field per line, with the file each value came from.

This skill is read only. It never writes to either file.

## Where the values come from

```sh
hp-config --source
```

`${CLAUDE_PLUGIN_ROOT}/scripts/hp-config` does the merge and prints one JSON envelope. Render that envelope. Do not parse `hyperpower.yml` or `hyperpower.local.yml` yourself: `hp-config` is the parser every stage of a run reads through, and a second parser here would report a config no run ever used.

| Envelope key | Holds |
|---|---|
| `config` | the effective config after the merge |
| `sources` | every dotted leaf path mapped to `hyperpower.yml`, `hyperpower.local.yml`, or `default` |
| `overrides` | the leaves `hyperpower.local.yml` changed, with both values |
| `unknown_keys` | keys not in the schema, with the file and value each came from |
| `type_errors` | values whose type disagrees with the schema |
| `hash` | the config hash, the same one `meta.json` records |
| `files` | the absolute path of each file read, `null` for one that is absent |

| Exit | Do |
|---|---|
| 0 | render the envelope |
| 78 | print `No hyperpower.yml. Run /hyperpower:init.` Stop. |
| 1 | print the file, the line number, and the parser error from stderr. Stop. |

The three sections below describe what the envelope means and how to lay it out. They do not describe work to do by hand.

## Merge rule

Per field, not per section. `hyperpower.local.yml` overrides `hyperpower.yml` at the leaf.

```yaml
# hyperpower.yml
models: { judgment: claude-opus-5, mechanical: claude-haiku-4-5 }

# hyperpower.local.yml
models: { judgment: claude-sonnet-5 }
```

Effective: `judgment` from local, `mechanical` from the committed file. A section-level replace would have dropped `mechanical`. Do not do that.

The exception is a list. A list is one leaf value, so a local `paths.source` replaces the committed list entirely. It does not concatenate. Label the whole list `hyperpower.local.yml`.

## Sources

| Label | Means |
|---|---|
| `hyperpower.yml` | committed, shared with the team |
| `hyperpower.local.yml` | your machine, gitignored |
| `default` | in neither file. The value shown is the built-in default. |

Print every field in the schema, including fields sitting at their default. The point of this command is what is in effect, not what someone typed.

## Output

Group by top-level key, in schema order: `version`, `project`, `paths`, `commands`, `gates`, `models`, `limits`, `memory`, `telemetry`, `voice`. Three columns: field, value, source.

```
project
  name                acme-web                  hyperpower.yml
  type                web-frontend              hyperpower.yml
  languages           [typescript, css]         hyperpower.yml
  package_manager     pnpm                      hyperpower.yml

commands
  install             pnpm install --frozen-lockfile   hyperpower.yml
  typecheck           tsc --noEmit                     hyperpower.yml
  test_scoped         pnpm vitest run {files}          hyperpower.yml
  e2e                 null                             hyperpower.yml

gates
  types.enabled       true                      hyperpower.yml
  types.blocking      true                      hyperpower.yml
  browser.enabled     false                     hyperpower.yml
  browser.reason      no dev_url configured     hyperpower.yml

models
  judgment            claude-sonnet-5         hyperpower.local.yml
  mechanical          claude-haiku-4-5          hyperpower.yml

limits
  rulebook_max_rules  30                        default
```

Print `null` for a null command. Never print a blank cell.

## Overrides summary

After the field list, print the local overrides on their own.

```
Overridden locally  1
  models.judgment    claude-opus-5 → claude-sonnet-5
```

No local file, or no differing field: print `No local overrides.` on one line.

Rank, never cap. More than five overrides: show five and say how many remain.

## Missing or broken files

| State | Print |
|---|---|
| No `hyperpower.yml` | `No hyperpower.yml. Run /hyperpower:init.` Stop. |
| `hyperpower.yml` only | the field list, then `No local overrides.` |
| Either file is unparseable | the file name, the line number, and the parser error. Stop. |
| A key not in the schema | the field list, then `Unknown key: <path>` under a `Not in schema` block |
| A value whose type disagrees with the schema | the field list, then the `type_errors` entries under a `Wrong type` block |

An unknown key is reported, never dropped and never silently accepted. Say which file it is in so the user can delete it. `hp-config` reports both blocks in `unknown_keys` and `type_errors`; print what is there and add nothing to it.

A wrong-typed value is still used, except a map replaced by a scalar, where the defaults are kept. Say which, so the user knows whether the run saw their value.

## Do not

- Do not write to `hyperpower.yml` or `hyperpower.local.yml`. Use `/hyperpower:paths` or an editor.
- Do not parse either YAML file yourself. Call `hp-config --source` and render what it prints.
- Do not merge section by section. That silently drops fields.
- Do not hide fields that sit at their default.
- Do not read config from anywhere else. Environment variables and CLI flags do not override these two files.
- Do not invent fields. The schema in `docs/configuration.md` is the whole surface.
