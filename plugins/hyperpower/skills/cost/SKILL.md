---
name: cost
description: Report tokens and money by stage, agent, model, or run. Reads .hyperpower/runs/*/usage.jsonl through scripts/hp-redact, which hashes file paths before anything is grouped, and prices it from the plugin's pricing.yml. Cache reads are shown in their own column because they dominate the token count and cost a tenth of fresh input. A price older than 90 days is labelled stale and still shown. A model with no price entry reports token counts and no money. Use /hyperpower:cost, with --since <7d|30d|all> and --by <stage|agent|model|run>.
---

# Cost

Report tokens from the run journal. Price them from `pricing.yml`. Never estimate a price
that is not in that file.

This skill is read only. It writes nothing and it uploads nothing.

## The rule

Cache reads get their own column. Never fold `cache_read` into an input total.

Cache reads dominate the token count and cost a tenth of fresh input. A total that mixes
them reads as far more spend than happened, and hides which stage is actually expensive.

## Flags

| Flag | Values | Default |
|---|---|---|
| `--since` | `7d`, `30d`, `all` | `30d` |
| `--by` | `stage`, `agent`, `model`, `run` | `stage` |

`--since` filters on the record `ts`, not on the run folder mtime.

## Step 1 - read pricing

Read `${CLAUDE_PLUGIN_ROOT}/pricing.yml`. Its own header documents every field and the
derived cache rates. Read them there. A second copy here drifts from the file it describes.

One fact that header does not carry: `usage.jsonl` records no cache-write count, so cache
writes are never priced. State that once in the footer and do not estimate them.

If `pricing.yml` is missing or unreadable, report token counts for everything and no money
at all. Say the file could not be read and name the path.

## Step 2 - read the records through hp-redact

Read one run folder at a time. A record carries no run id, so `cat` into one pipe loses the
run boundary and `--by run` has nothing to group on. The folder name is the only run id
there is.

```sh
for f in .hyperpower/runs/*/usage.jsonl; do
  echo "== run $(basename "$(dirname "$f")")"
  ${CLAUDE_PLUGIN_ROOT}/scripts/hp-redact --stdin < "$f"
done
```

Price what it prints. It hashes file paths and leaves `stage`, `agent`, `model`, the token
counts, and `ts` untouched, so every number below is computed from the same values as
before. Redacting the finished table instead misses every path folded into a group label.

## Step 3 - price each record

Three counters, three rates. Per record:

1. fresh input = `input_tokens` x `input` / 1,000,000
2. cache read  = `cache_read` x `input` x `cache_multipliers.read` / 1,000,000
3. output      = `output_tokens` x `output` / 1,000,000

`input_tokens` and `cache_read` are separate counters in the record. Do not subtract one
from the other.

Gate records carry no token counts and cost nothing. Exclude them from every total.

## Step 4 - handle prices that cannot be trusted

Two cases. Both still show the tokens.

| Case | Money column | Label |
|---|---|---|
| `last_verified` more than 90 days before today | shown | `stale, verified <date> (<n> days)` |
| model absent from `pricing.yml` | `-` | `no price entry` |

A stale price is shown and marked unverified. It is never presented as current, and it is
never dropped for being old.

A missing entry never borrows a rate from another model. Not from the same family, not from
one with the same context size, not from the tier above or below. Tokens only.

Repeat every stale or unpriced row as a footer line under the table. A label inside a wide
table is easy to miss.

## Step 5 - group and total

`--by` selects the group column: `stage`, `agent`, `model` one row per model id, or `run`
newest first.

Sort rows by cost descending. Rows with no money sort last, by total tokens descending.
Print a totals row.

Money uses two decimals. A non-zero total under one cent prints `<$0.01`, never `$0.00`.
Tokens print as `k` or `M` with one decimal.

## Output

```
Cost - last 30 days, 14 runs, by stage

  stage         calls    fresh in   cache read      out      cost
  build            31      412.0k        3.10M    38.2k     $3.06
  review           28      288.4k        2.44M    21.0k     $2.06
  plan             14      102.1k      880.0k      9.4k     $0.75
  fix               9       88.0k      610.0k      7.7k     $0.69
  understand       14       61.7k      402.0k      3.1k     $0.36
  ---
  total            96      952.2k        7.44M    79.4k     $6.92

  Cache reads are 89% of tokens and 11% of spend.
  Cache writes are not recorded, so the total is a lower bound.
```

A stale row carries its label in place, after the cost column:
`stale, verified 2026-01-14 (236 days)`.

## Redaction

Per-run journals keep real paths, by design. They already live inside the repo they
describe. This is a read-side transform: it protects the view, not the file on disk.

A cost table groups by stage, agent, model, or run, and none of those is a path. Paths
arrive in the free-text `outcome` string of a failed call, so the pipe in Step 2 is what
keeps them out of the footer and out of any row you quote.

Call the report redacted. Never call it clean. Three things survive it:

1. A name with no extension and no slash is not a path here. `Makefile` and `my notes`
   print as written.
2. A path splits at any character that cannot appear in one, and each piece is redacted only
   if that piece is path-shaped alone. `src\api\settings.ts` prints as
   `src\api\path:567e5738`, so part of the name stays while the line reads as redacted.
3. `outcome` is free text. It can name a file in words, which redaction never touches.

A collision between two 8-hex tokens cannot merge a cost row, because a cost table groups by
stage, agent, model, or run and never by file. `/hyperpower:usage` carries that caveat.

When `telemetry.redact_paths` is false, `hp-redact` passes the records through and says so
on stderr. Print that line above the table. `/hyperpower:telemetry` holds the full rule.

## Config

If `hyperpower.yml` exists, read `models.judgment` and `models.mechanical`. Report any
configured model with no entry in `pricing.yml`, even when no call used it yet. That
surfaces a missing price before the spend, not after.

Without `hyperpower.yml`, price only the models the records name. Do not ask the user to
create a config.

## Reading the result

| Pattern | Means |
|---|---|
| One stage holds most of the spend | check it earns it with `/hyperpower:usage --by stage` |
| Cache read share falling | context is being rebuilt instead of reused |
| Cost rising while gate failures and fix rounds are flat | paying for stages that are not earning it |

## Do not

- Do not fold cache reads into the input column, or into one combined token number.
- Do not guess a price. A model with no entry gets token counts and a blank money column.
- Do not hide a stale price, and do not silently refresh `pricing.yml`. Editing rates is a
  separate change with a new `last_verified`.
- Do not price gate records. They carry no tokens.
- Do not fetch prices from the network. This command reads local files, runs `hp-redact`,
  and does nothing else.
- Do not read `usage.jsonl` straight off disk to save a pipe, and do not hash a path by
  hand. `hp-redact` is the one implementation, and a second one gives a different token for
  the same file.
