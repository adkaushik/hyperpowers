# Analytics and privacy

## Privacy first

Nothing leaves your machine.

There is no remote destination in the codebase. There is no opt-in that would create one.
`telemetry.destination` accepts exactly one value: `local`.

All data is written to files inside your repository. You can read them, diff them, and
delete them.

```
/hyperpower:telemetry purge
```

Deletes everything recorded and tells you how many files it removed.

## What is recorded

One line per model call, in `.hyperpower/runs/<run-id>/usage.jsonl`:

```jsonl
{"ts":"2026-09-07T11:04:12Z","stage":"review","agent":"reviewer","model":"claude-opus-5","input_tokens":18422,"output_tokens":1130,"cache_read":16000,"duration_ms":9400,"outcome":"ok"}
```

Gate results go to the same file with `stage: "gate:types"` and no token counts.

Run folders are gitignored by default. The sheets (`backlog`, `hygiene`) are committed,
because they are meant to be reviewed by people.

### Path redaction

When `telemetry.redact_paths` is true, file paths are hashed before being written to any
aggregate view. Per-run journals keep real paths, because they already live inside the
repo they describe.

## Usage

```
/hyperpower:usage --since 7d --by stage
```

Reports run counts, stage pass rates, fix-loop round distribution, gate failure counts by
gate, assumption verified/refuted/unresolved ratio, and median run duration.

### The two numbers that matter

1. **Gate failure rate.** How often the harness produces work that does not pass.
2. **Fix-loop rounds per task.** How many attempts it takes to get there.

Both rising over time means the rulebook has drifted from the codebase. Fix:

```
/hyperpower:init --refresh
```

Neither number rising while cost rises means you are paying for stages that are not
earning it. Check `--by stage`.

## Cost

```
/hyperpower:cost --since 30d --by model
```

Tokens and money by stage, agent, model, or run.

Cache reads are shown separately. They dominate the token count and cost a fraction of
fresh input, so a total that mixes them is misleading.

### Prices

Prices live in `pricing.yml` inside the plugin, each with a `last_verified` date.

When a price is older than 90 days it is labelled stale in the output. The number is still
shown, marked as unverified. It is never silently presented as current.

If a model in your config has no price entry, the report shows token counts for it and no
money, rather than guessing.

## Turning it off

```
/hyperpower:telemetry off
```

Stops recording. The harness still works. `usage` and `cost` will report only what was
recorded before you turned it off.
