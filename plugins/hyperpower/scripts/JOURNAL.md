# Run journal

A run is a folder: `.hyperpower/runs/<run-id>/`. Sessions are disposable, the folder is not.

Write it with `hp-journal`. Read it with `/hyperpower:why`, `/hyperpower:resume`,
`/hyperpower:usage`, `/hyperpower:cost`, `/hyperpower:correct`, the archivist, and the
promoter.

```sh
hp-journal new --task-class feature          # prints the run id
hp-journal step 4f2a plan --file plan.json
hp-journal hash 4f2a plan --files src/a.ts,src/b.ts --prompt-file plan.prompt
hp-journal usage 4f2a --stage plan --agent planner --model claude-opus-5 --input 900 --output 120
hp-journal mistake 4f2a --kind gate_failed --key generated-import-drift --ref .hyperpower/runs/4f2a/gates.json
hp-journal drift 4f2a --from gates
hp-journal finish 4f2a --outcome ok
```

`latest` is a valid run id everywhere. It resolves to the newest recorded run.

## Layout

| File | Written by | Read by |
|---|---|---|
| `meta.json` | `hp-journal new`, `hp-journal finish` | why, resume, review, archivist, telemetry |
| `<step>.json` | `hp-journal step`, `hp-journal hash` | why, resume, correct, usage, archivist |
| `usage.jsonl` | `hp-journal usage` | usage, cost, telemetry |
| `mistakes.jsonl` | `hp-journal mistake`, the archivist | promoter, why, telemetry |
| `corrections.jsonl` | `/hyperpower:correct` | why, resume, archivist |
| `resume.jsonl` | `/hyperpower:resume` | telemetry |
| `gates/<gate>.log` | `gates/_lib.sh`, when `HYPERPOWER_RUN_DIR` is set | the gate report, telemetry |
| `superseded/<ts>/` | `/hyperpower:resume` | history |

`hp-journal` writes the first four. It never writes `corrections.jsonl`, `resume.jsonl`,
the gate logs, or `superseded/`. Those belong to the components named above.

A missing `<step>.json` means the stage was skipped. It is not a failure and not a pass.

## Run ids

The id is `sha256("<base_sha>:<counter>")` truncated to four hex characters.

1. It is derived from the base sha, not from a clock and not from randomness. The same base
   sha and counter always give the same id.
2. `hp-journal new` claims the folder with `mkdir`, which is atomic. A caller that loses the
   race increments the counter and tries again, so two callers never share a folder.
3. The counter and the derivation are recorded in `meta.json`.
4. After 10000 counters the id widens to eight hex characters. After that `new` fails
   rather than reuse a folder.

Do not parse a run id for meaning. It is an identifier, not the base sha.

## meta.json

```json
{
  "run": "4f2a",
  "schema": 1,
  "base_sha": "a3f19c2d4e5f60718293a4b5c6d7e8f901234567",
  "task_class": "feature",
  "models": {"judgment": "claude-opus-5", "mechanical": "claude-haiku-4-5"},
  "config_hash": "sha256:dc668d82481ce1ed6872c91d71ad12613231cf3394cc80197588a5bcf29d18c2",
  "config_files": ["hyperpower.yml", "hyperpower.local.yml"],
  "started_at": "2026-09-07T11:04:12Z",
  "finished_at": null,
  "outcome": null,
  "id_counter": 0,
  "id_derivation": "sha256(<base_sha>:<counter>) truncated to 4 hex characters"
}
```

| Field | Holds |
|---|---|
| `run` | the run id. The jsonl records use the same key. |
| `base_sha` | full sha the run works against. `--base` overrides `git rev-parse HEAD`. |
| `task_class` | what the router picked. `null` when `--task-class` was omitted. |
| `models` | the tiers in effect when the run started, from `models` in the config |
| `config_hash` | `hp-config --hash` at start. Resume compares it and treats a difference as drift on every step. |
| `outcome` | `null` until `finish`, then `ok`, `failed`, `blocked`, or `aborted` |

`hp-journal new` exits 78 when there is no `hyperpower.yml`. The model tiers and the config
hash come from the config, and the harness does not guess a config.

## `<step>.json`

Nine step names, in pipeline order: `route`, `understand`, `plan`, `design`, `build`,
`gates`, `review`, `fix`, `render`. Any other name is refused.

`hp-journal step` takes the stage's own contract on stdin or in a file, then stamps three
fields on top of it:

| Field | Value |
|---|---|
| `step` | the step name. A contract naming a different step is refused. |
| `run_id` | the run id. A contract naming a different run is refused. |
| `recorded_at` | ISO 8601 UTC, when the contract was written |

Everything else in the contract is written through untouched. Field names are the agent's,
not the journal's: `build.json` carries `changed_files` and `assumptions` because
`agents/builder.md` says so.

`step` and `hash` can run in either order. `step` keeps the `prompt_hash`, `files_read`, and
`cache_key` already on disk unless the incoming contract carries them.

Do not apply ADHD shaping or the cap-at-five rule to a step contract. It is an
agent-to-agent handoff. Truncating it drops work.

## The cache key

`hp-journal hash` computes it and stores the three inputs separately, so a drift report can
name which one moved.

```json
"prompt_hash": "sha256:08cf...",
"files_read": ["src/a.ts", "src/b.ts"],
"cache_key": {
  "key": "sha256:ae6e...",
  "prompt_hash": "sha256:08cf...",
  "upstream_step": "plan",
  "upstream_hash": "sha256:1c29...",
  "files_hash": "sha256:9fb9...",
  "blobs": {"src/a.ts": "41715495f45f651e6cf7d38f58a3d512abcfa440"},
  "hashed_at": "2026-09-07T11:04:12Z"
}
```

| Input | Computed from |
|---|---|
| `prompt_hash` | `--prompt-file`, `--prompt`, or `--prompt-hash`. Absent all three, the value already on disk. |
| `upstream_hash` | sha256 of the nearest earlier recorded `<step>.json`, as it is on disk. `null` for the first step. |
| `files_hash` | sha256 over `<path> <blob>` lines, sorted by path |
| `blobs` | the value `git hash-object <path>` prints, per file. `null` when the file is gone. |
| `key` | sha256 of the three digests joined by newlines |

The blob hash is computed in process, from the bytes on disk. It equals `git hash-object`
and needs no git subprocess, so an uncommitted edit counts as drift.

Do not key a step on the prompt alone. That is the bug that lets a resumed run review code
that no longer exists.

## drift

`hp-journal drift <run> --from <step>` prints the format `skills/resume/SKILL.md` specifies.

```
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
```

1. `ok` is lowercase. `DRIFTED` and `UNHASHED` are uppercase. No emoji and no tick marks.
2. Step names are padded to the longest printed name plus three spaces.
3. A drifted line names the file count when any file changed. When no file changed, it names
   the input that did: `DRIFTED — upstream plan.json changed since this step`, or
   `DRIFTED — prompt changed since this step`. A second drifted input gets its own line
   under the first, indented to the value column.
4. `UNHASHED — no cache key recorded for this step` means the step was never hashed. Treat
   it as drifted. It is not `ok`.
5. Files matched by `paths.ignore` are skipped. Without a config the whole recorded list is
   compared, and a note says so.
6. A `config_hash` that no longer matches prints
   `Config hash changed since this run. Treat every step as drifted.` after the step lines.
7. The question prints only when a step earlier than the requested one drifted. When the
   requested step is itself the earliest drifted one, resume replays from it and there is
   nothing to offer instead.

`--json` prints the whole comparison: per step `state`, `changed_files`, the changed file
list, and a `drifted` object with a boolean for each of the three inputs.

## usage.jsonl

One line per model call. The shape is the one `docs/analytics.md` documents.

```jsonl
{"ts":"2026-09-07T11:04:12Z","stage":"review","agent":"reviewer","model":"claude-opus-5","input_tokens":18422,"output_tokens":1130,"cache_read":16000,"duration_ms":9400,"outcome":"ok"}
```

| Field | Holds |
|---|---|
| `ts` | ISO 8601 UTC of the call |
| `stage` | pipeline stage, or `gate:<name>` for a gate result |
| `agent` | agent role that made the call. `null` when the caller passed no `--agent`. |
| `model` | model id, as it appears in `pricing.yml` |
| `input_tokens` | fresh input tokens. Cache reads are not in this number. |
| `cache_read` | cached input tokens. `0` when nothing was cached. |
| `duration_ms` | wall clock. `null` when the caller passed no `--duration-ms`. |
| `outcome` | `ok` for a pass. Anything else is a failure, and the string is the reason. |

A gate result carries no model call, so it carries no model, agent, or token counts:

```jsonl
{"ts":"2026-09-07T11:04:15Z","stage":"gate:types","duration_ms":3200,"outcome":"ok"}
```

`--stage` is not restricted to the nine step names. A stage that consumes tokens without
writing a step contract, such as `adjudicate`, records under its own name.

Do not fold `cache_read` into `input_tokens`. Cache reads dominate the token count and cost
a fraction of fresh input, so a combined number reads as far more spend than happened.

## mistakes.jsonl

Four keys, no timestamp. The promoter scans this file and nothing else, so the lines stay
small.

```jsonl
{"run":"4f2a","kind":"assumption_refuted","key":"settings-api-shape","ref":"decisions/2026-09-07-preview-masking-location.md"}
```

| `kind` | Emit when | Promotes at |
|---|---|---|
| `forever_correction` | a correction used `--scope forever` | 1 distinct run |
| `assumption_refuted` | an assumption ended `status: refuted` | 3 distinct runs |
| `gate_failed` | a gate exited non-zero | 3 distinct runs |
| `finding_confirmed` | a review finding came back CONFIRMED | 3 distinct runs |

`key` is a stable kebab-case slug naming the cause, not the instance: `settings-api-shape`,
never `run-4f2a-assumption-a1`. The promoter counts the key across runs, so an unstable key
disables promotion. Lowercase letters, digits, and hyphens are the whole alphabet.

`ref` is a repo-relative path to the evidence. It defaults to the run's `meta.json`. Name
the decision record or the journal file instead, because the promoter skips a candidate
whose `ref` does not resolve.

## corrections.jsonl

Written by `/hyperpower:correct`, not by `hp-journal`. Documented here because it lives in
the run folder and resume replays from it.

```jsonl
{"run":"4f2a","step":"plan","assumption":"a1","key":"settings-api-shape","text":"settings API returns { items: [] }","scope":"run","challenged":true,"ts":"2026-09-07T11:04:12Z"}
```

## resume.jsonl

Written by `/hyperpower:resume`, one line per replay: the timestamp, the `--from` step, the
answer taken, and the drifted step names.

## Concurrency

Every subcommand is safe to call from parallel agents.

| Write | Mechanism |
|---|---|
| `usage.jsonl`, `mistakes.jsonl` | `O_APPEND`, one `write()` per line. Lines are capped at 4096 bytes, so the write is atomic. |
| `meta.json`, `<step>.json` | an `O_EXCL` lock file beside the target, then write a temp file and `os.replace` |
| a run folder | `mkdir`, which fails rather than reuse an existing folder |

A record larger than 4096 bytes is refused with its byte count. Do not raise the cap. Put
the long content in a `<step>.json` and reference it.

A lock older than 60 seconds belonged to a process that died, and is broken automatically.
A lock held by a live writer waits 10 seconds, then reports which file is locked.

## Commands

| Command | Does |
|---|---|
| `hp-journal new [--task-class C] [--base SHA]` | create the folder and `meta.json`, print the run id |
| `hp-journal step <run> <step> --file F \| --stdin` | write that step's output contract |
| `hp-journal usage <run> --stage S --model M --input N --output N` | append one usage record |
| `hp-journal mistake <run> --kind K --key K [--ref R]` | append one failure event |
| `hp-journal hash <run> <step> --files F1,F2` | compute and store the step's cache key |
| `hp-journal drift <run> [--from STEP]` | re-hash the working tree, report per-step drift |
| `hp-journal finish <run> --outcome O` | stamp `outcome` and `finished_at` |
| `hp-journal list [--limit N]` | recorded runs, newest first |
| `hp-journal path <run>` | the absolute path to a run folder |

Every subcommand takes `--root DIR`. Without it the root is `HYPERPOWER_REPO_ROOT`, then the
git top level, then the nearest directory holding `hyperpower.yml` or `.hyperpower/`.

## Exit codes

| Code | Means |
|---|---|
| 0 | written |
| 1 | bad input, or a write that failed. The message names the cause and the fix. |
| 78 | no `hyperpower.yml`. `hp-journal new` and `hp-config` return this. |

## Config

`hp-config` reads `hyperpower.yml`, merges `hyperpower.local.yml` over it field by field,
and prints JSON. `hp-journal` imports it for the model tiers, the config hash, and
`paths.ignore`.

| Flag | Prints |
|---|---|
| none | the effective config, indented |
| `--json` | the same, on one line |
| `--source` | an envelope: `config`, `sources`, `overrides`, `unknown_keys`, `type_errors`, `hash` |
| `--hash` | the config hash alone, which is what `meta.json` records |

`sources` maps every dotted leaf path to `hyperpower.yml`, `hyperpower.local.yml`, or
`default`. A list is one leaf, so a local list replaces the committed list whole.

A key not in `docs/configuration.md` lands in `unknown_keys` with its file and value. It is
never merged and never dropped silently. A value whose type disagrees with the schema lands
in `type_errors` and is still used, except a map replaced by a scalar, where the defaults
are kept.

The parser supports nested maps, block lists of scalars, inline maps, inline lists, quoted
and unquoted scalars, `null`, booleans, integers, floats, and `#` comments. It rejects
anchors, aliases, tags, block scalars, lists of maps, multiple documents, duplicate keys,
and tabs in indentation, naming the file and line.

## Do not

- Do not write a run folder by hand. `hp-journal new` derives the id and records the config
  hash the resume drift check needs.
- Do not delete a run folder to clean up. `/hyperpower:telemetry purge` is the one path that
  removes recorded telemetry.
- Do not append to `usage.jsonl` or `mistakes.jsonl` with a shell redirect. Two agents doing
  that interleave a partial record, and the file stops parsing.
- Do not put a timestamp in a mistake line. The promoter counts distinct `run` values, and a
  bigger line makes the scan more expensive for nothing.
- Do not report a step as `ok` because it has no cache key. An unhashed step was never
  verified.
