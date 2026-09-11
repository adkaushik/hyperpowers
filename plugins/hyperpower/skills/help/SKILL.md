---
name: help
description: List every hyperpower command in plain language - what it does, when you would reach for it, and an example. Grouped by situation rather than by internals. Run /hyperpower:help for all of them, or /hyperpower:help <command> for one.
---

# help

Show the commands. Plain language, grouped by when you would want them.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/hp-help
```

| Argument | Gives |
|---|---|
| none | every command, grouped, with what and when |
| `<command>` | one command, with an example. A fragment matches several. |
| `--verbose` | every command with its example |
| `--check` | only drift between the help table and the skills on disk |

Print what the script returns. Do not rewrite it into your own words — the wording is
maintained in one place so it cannot drift from what the commands actually do.

## Answer the question that was asked

Someone typing `/hyperpower:help` wants orientation. Someone asking "how do I check what it
did" wants one command, not twenty-five.

When the question names a situation rather than a command, run the script, pick the two or
three commands that fit, and say why. Do not paste the whole list at a specific question.

| They ask | Lead with |
|---|---|
| where do I start | `init`, then `route` |
| is this thing even on | `status` |
| it said done but it was not | `why --assumptions`, then `review` |
| this is taking forever | `route` before `run`, and `status --watch` |
| what did it cost | `cost --by stage` |
| the code looks AI-written | `humanize` |
| I disagree with what it chose | `council`, or `standup` if the tradeoff is unsettled |

## The one worth saying unprompted

`route` before `run`. It prints the stage list and an estimate from this repo's own past
runs, then stops. It costs nothing and writes nothing.

Someone who does not know that types `run` on an exploratory question and waits twenty
minutes for a plan they never wanted.

## Do not

- Do not invent a command. Run the script; what it prints is what exists.
- Do not paste all twenty-five commands in answer to a specific question.
- Do not describe a flag the script does not list.
- Do not rewrite the descriptions. One source, or it drifts.
