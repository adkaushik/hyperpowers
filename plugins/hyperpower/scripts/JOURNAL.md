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
hp-journal correction 4f2a --step plan --assumption a1 --text "it returns { items: [] }" --scope run
hp-journal resume-event 4f2a --from gates --decision build --drifted build
hp-journal drift 4f2a --from gates
hp-journal finish 4f2a --outcome ok
```

`latest` is a valid run id everywhere. It resolves to the newest recorded run.

## The repo root

One rule, three sources, in this order. This section is the statement of it.

| Order | Source |
|---|---|
| 1 | `HYPERPOWER_REPO_ROOT`, when it is set and not empty |
| 2 | the git top level, from `git rev-parse --show-toplevel` |
| 3 | the nearest directory at or above the working directory holding `hyperpower.yml` |

Every component that resolves a root follows this order: `hp-journal`, `hp-config`, and
`gates/_lib.sh`. A component that resolves it differently reads a different repo, so a gate
writes its log into one journal while the run writes its contracts into another, and
nothing in the output shows the split.

Two additions, and no others:

1. An explicit `--root DIR` wins over all three. A path the caller passed is not a guess.
2. After the three, `hp-journal` accepts a directory holding `.hyperpower/`, so `drift`,
   `list`, and `path` still read a journal in a repo whose `hyperpower.yml` was deleted.
   Subcommands that need the config still exit 78 there.

Do not reorder the three. Do not add a fourth source. Do not honour `HYPERPOWER_REPO_ROOT`
in one script and ignore it in another: that variable is how a worktree, a sandbox, and a
gate subprocess name a root that is not the working directory.

## Layout

| File | Written by | Read by |
|---|---|---|
| `meta.json` | `hp-journal new`, `hp-journal finish` | why, resume, review, archivist, telemetry |
| `<step>.json` | `hp-journal step`, `hp-journal hash` | why, resume, correct, usage, archivist |
| `usage.jsonl` | `hp-journal usage` | usage, cost, telemetry |
| `mistakes.jsonl` | `hp-journal mistake`, the archivist | promoter, why, telemetry |
| `corrections.jsonl` | `hp-journal correction` and `correction-applied`, for `/hyperpower:correct` and `/hyperpower:resume` | why, resume, archivist |
| `resume.jsonl` | `hp-journal resume-event`, for `/hyperpower:resume` | telemetry |
| `gates/<gate>.log` | `gates/_lib.sh`, when `HYPERPOWER_RUN_DIR` is set | the gate report, telemetry |
| `superseded/<ts>/` | `/hyperpower:resume` | history |

`hp-journal` writes every file in that table except the gate logs and `superseded/`. A
command that wants a record written calls the subcommand for it. It does not append to a
`.jsonl` itself: one writer per file is what keeps the record shapes from forking.

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

`--task-class` is checked against the `classes:` map in `task-classes.yml`. A class outside
that file is refused with the valid list, and the run folder is not created. The check
happens before the folder is claimed, so a refused class leaves nothing behind.

The reason is grouping. `/hyperpower:usage` groups runs by this field, and
`schemas/plan.json` carries the same seven values. A class no other component knows
produces a run that every aggregate silently drops. Omitting `--task-class` is fine and
records `null`. Inventing a class is not.

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

### Every step is validated before it is recorded

`hp-journal step` runs `hp-validate <step> --stdin` on the record it is about to write,
stamped fields and all, and writes nothing when the schema rejects it. The message names the
source, lists every violation with its JSON path, and exits 1.

```
hp-journal: plan.json is not a valid plan contract, so it was not written.
invalid: stdin against /path/to/schemas/plan.json
  $.status                     missing required field
  $.assumptions[0].confidence  "very-low" is not one of: "high", "medium", "low"
2 violations.
Fix the contract, or pass --no-validate to record it unchecked.
```

The check is here and not only in `skills/run/SKILL.md` because prose binds one caller. Any
skill, agent, or shell loop that calls `hp-journal step` gets the same refusal.

`hp-validate` is the one implementation of the check. `hp-journal` shells out to it rather
than reading the schema itself, so there is no second implementation to drift.

| `hp-validate` exit | `hp-journal step` does |
|---|---|
| 0 | writes the contract |
| 1 | refuses, and prints every violation |
| 2 | refuses. The flags were wrong, so nothing was checked. |
| 78 | refuses. There is no usable schema for that step, so nothing was checked. |
| script missing, or will not run | refuses. Reinstall the plugin. |

`--no-validate` records the contract unchecked. Two cases are legitimate:

1. A stage whose schema does not exist yet, while it is being written.
2. Importing a run folder recorded against an older schema, for forensics.

Do not pass `--no-validate` in a pipeline run, and do not pass it to get past violations you
have not read. `/hyperpower:resume`, `/hyperpower:why`, and the archivist read these
files by their schema, and a contract that does not match reads as a stage that produced
nothing.

### A step file with no contract

`hash` writes `<step>.json` when it runs before the stage returns, which is the order
`skills/run/SKILL.md` uses. That file holds only `step`, `run_id`, `prompt_hash`,
`files_read`, and `cache_key`. It is a placeholder, not a recorded stage.

`drift` reports it as `UNRECORDED`. That is the fix for it, chosen over making `hash` refuse
to create the file, because refusing would break the documented hash-validate-step order and
leave the cache key nowhere to live.

`upstream_step` still picks a placeholder as the nearest earlier step. Leave that alone.
The file changes when the real contract lands, so the downstream step then reports
`DRIFTED — upstream <step>.json changed since this step`, which is the truth. Skipping
placeholders would silence it.

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
| `key` | sha256 over the three digests, one per line. Exactly as described below. |

### The key, byte for byte

Three lines, each terminated by `\n`, in this order: `prompt_hash`, `upstream_hash`,
`files_hash`. The third line carries a trailing newline like the first two.

```
prompt_hash + "\n" + upstream_hash + "\n" + files_hash + "\n"
```

A digest that is `null` or empty is written as the literal four-character string `none`.
`upstream_hash` is `null` for a first recorded step, so `none` is what it hashes.

Each digest is the `sha256:<hex>` string as it is stored, prefix included. The body is
encoded UTF-8, hashed with sha256, and the key is `sha256:` followed by the hex digest.

Reproduce a recorded key from its own `cache_key` block:

```sh
printf '%s\n%s\n%s\n' "$prompt_hash" "${upstream_hash:-none}" "$files_hash" \
  | python3 -c 'import hashlib,sys; print("sha256:"+hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
```

That command prints the value in `cache_key.key`. A second implementation that joins the
three with newlines and stops, or that omits the `none` sentinel, computes a different key
for the same step and reports drift that did not happen.

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

1. `ok` is lowercase. `DRIFTED`, `UNHASHED`, and `UNRECORDED` are uppercase. No emoji and no
   tick marks.
2. Step names are padded to the longest printed name plus three spaces.
3. A drifted line names the file count when any file changed. When no file changed, it names
   the input that did: `DRIFTED — upstream plan.json changed since this step`, or
   `DRIFTED — prompt changed since this step`. A second drifted input gets its own line
   under the first, indented to the value column.
4. `UNHASHED — no cache key recorded for this step` means the step was never hashed. Treat
   it as drifted. It is not `ok`.
5. `UNRECORDED — cache key only, no step contract recorded` means `hash` created the file
   and no stage ever wrote a contract into it. Treat it as drifted. It is not `ok`, and it
   is not skipped: a skipped stage has no file at all.
6. Files matched by `paths.ignore` are skipped. Without a config the whole recorded list is
   compared, and a note says so.
7. A `config_hash` that no longer matches prints
   `Config hash changed since this run. Treat every step as drifted.` after the step lines.
8. The question prints only when a step earlier than the requested one drifted. When the
   requested step is itself the earliest drifted one, resume replays from it and there is
   nothing to offer instead.

`--json` prints the whole comparison: per step `state`, `changed_files`, the changed file
list, and a `drifted` object with a boolean for each of the three inputs. `state` is `ok`,
`drifted`, `unhashed`, or `no_contract`. Only `ok` may be replayed over.

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

One line per correction `/hyperpower:correct` made. `hp-journal correction` writes it.

```sh
hp-journal correction 4f2a --step plan --assumption a1 \
  --text "settings API returns { items: [] }" --scope run --challenged
```

```jsonl
{"run":"4f2a","step":"plan","assumption":"a1","key":"settings-api-shape","text":"settings API returns { items: [] }","scope":"run","challenged":true,"ts":"2026-09-07T11:04:12Z"}
```

| Field | Holds |
|---|---|
| `run` | the run id, the same key the other jsonl records use |
| `step` | the step whose assumption was corrected |
| `assumption` | the id that step declared. An id it did not declare is refused. |
| `key` | stable kebab-case slug naming the cause. Derived from `--text` when `--key` is omitted. |
| `text` | the correction itself |
| `scope` | `once`, `run`, or `forever` |
| `challenged` | true when the code contradicted the correction and the challenge was printed |
| `ts` | ISO 8601 UTC |
| `applied` | absent until a replay used a `once` correction. See below. |

The command refuses a correction against an assumption the step never declared, and names
the ids it did declare. `/hyperpower:correct` edits an existing record. It never invents
one.

Pass `--key` when the promoter must count one cause across runs that word it differently. A
derived key is stable for one wording and changes when the wording changes.

`hp-journal correction` writes `corrections.jsonl` and nothing else. The other two writes in
`skills/correct/SKILL.md` step 3 are `hp-journal mistake` for the promoter and the
assumption's own `status` in `<step>.json`.

### The once lifecycle

A `once` correction applies to the next replay of its own step, and then retires. Three
commands, one owner each.

| Step | Command | Writes |
|---|---|---|
| record it | `hp-journal correction ... --scope once` | the entry, with no `applied` field |
| find it before a replay | `hp-journal corrections <run> --step plan --pending` | nothing |
| retire it after the replay | `hp-journal correction-applied <run> --step plan` | `applied: true` on every matching entry |

`correction-applied` is the one writer of `applied`. `hp-journal correction` never sets it,
and nothing else may.

Order matters. Call `correction-applied` after the replay wrote that step's `<step>.json`,
never before. A replay that fails or is interrupted first must leave the entry unstamped, so
the next replay applies the correction again. Stamping first drops the correction silently.

The rewrite keeps every other line byte for byte, including a line that does not parse.
Such a line is reported by number and kept, because deleting it would delete a correction a
human made.

`run` and `forever` corrections are never stamped. `run` stands for the life of the run, and
`forever` is retired only by a promoter demotion.

## resume.jsonl

One line per `/hyperpower:resume` replay. `hp-journal resume-event` writes it.

```sh
hp-journal resume-event 4f2a --from gates --decision build --drifted build
```

```jsonl
{"run":"4f2a","ts":"2026-09-07T11:04:12Z","from":"gates","decision":"build","drifted":["build"]}
```

| Field | Holds |
|---|---|
| `run` | the run id |
| `ts` | ISO 8601 UTC of the replay |
| `from` | the step `--from` named |
| `decision` | the answer the human gave |
| `drifted` | the drifted step names, sorted into pipeline order |

`decision` is one of three shapes: a step name, which replays from there; `<step>-anyway`,
which replays from the requested step over the drift; or `abort`. Anything else is refused
with the vocabulary.

`--drifted` takes step names, not a count. The count is the length of the list, and a name
tells a reader which step moved. `--drifted` is repeatable and comma-separated.

Append the record after the invalidation, not before. `/hyperpower:resume` moves the
invalidated contracts into `superseded/<ts>/` first, so the `--from` step may have no file
on disk by then. `resume-event` does not require one.

## Concurrency

Every subcommand is safe to call from parallel agents.

| Write | Mechanism |
|---|---|
| `usage.jsonl`, `mistakes.jsonl`, `resume.jsonl` | `O_APPEND`, one `write()` per line. Lines are capped at 4096 bytes, so the write is atomic. |
| `meta.json`, `<step>.json` | an `O_EXCL` lock file beside the target, then write a temp file and `os.replace` |
| `corrections.jsonl` | the same lock, taken by both the append and the `applied` rewrite |
| a run folder | `mkdir`, which fails rather than reuse an existing folder |

`corrections.jsonl` is the one `.jsonl` with a rewriter, so its appends take the lock too.
Without that, a correction appended during a `correction-applied` rewrite is lost.

A record larger than 4096 bytes is refused with its byte count. Do not raise the cap. Put
the long content in a `<step>.json` and reference it.

A lock older than 60 seconds belonged to a process that died, and is broken automatically.
A lock held by a live writer waits 10 seconds, then reports which file is locked.

## Commands

| Command | Does |
|---|---|
| `hp-journal new [--task-class C] [--base SHA]` | create the folder and `meta.json`, print the run id |
| `hp-journal step <run> <step> --file F \| --stdin` | validate that step's contract, then write it |
| `hp-journal usage <run> --stage S --model M --input N --output N` | append one usage record |
| `hp-journal mistake <run> --kind K --key K [--ref R]` | append one failure event |
| `hp-journal correction <run> --step S --assumption A --text T --scope C` | append one correction, print its key |
| `hp-journal corrections <run> [--step S] [--scope C] [--pending]` | print the corrections recorded for a run |
| `hp-journal correction-applied <run> --step S` | stamp `applied: true` on the `once` corrections a replay used |
| `hp-journal resume-event <run> --from STEP --decision D [--drifted S1,S2]` | append one replay record |
| `hp-journal hash <run> <step> --files F1,F2` | compute and store the step's cache key |
| `hp-journal drift <run> [--from STEP]` | re-hash the working tree, report per-step drift |
| `hp-journal finish <run> --outcome O` | stamp `outcome` and `finished_at` |
| `hp-journal list [--limit N]` | recorded runs, newest first |
| `hp-journal path <run>` | the absolute path to a run folder |

Every subcommand takes `--root DIR`. Without it the root resolves the way "The repo root"
above states.

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
- Do not append to any `.jsonl` in a run folder with a shell redirect. Two agents doing that
  interleave a partial record, and the file stops parsing. Every one of the four has a
  subcommand: `usage`, `mistake`, `correction`, `resume-event`.
- Do not put a timestamp in a mistake line. The promoter counts distinct `run` values, and a
  bigger line makes the scan more expensive for nothing.
- Do not report a step as `ok` because it has no cache key. An unhashed step was never
  verified.
- Do not report a step as `ok` because a file exists for it. A file holding only a cache key
  is a placeholder `hash` wrote, and no stage recorded a contract into it.
- Do not record a step contract without validating it. `--no-validate` exists for a missing
  schema and for importing an old run, not for a contract whose violations you did not read.
- Do not set `applied` on a correction from anywhere but `hp-journal
  correction-applied`, and do not set it before the replay wrote its contract.
- Do not invent a task class. `task-classes.yml` is the whole vocabulary, and `null` is the
  value for a run that was never routed.
