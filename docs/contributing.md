# Contributing

## Repository layout

```
hyperpowers/
  .claude-plugin/marketplace.json
  plugins/hyperpower/
    .claude-plugin/plugin.json
    agents/           one file per agent role
    skills/           process skills, vendored and original
    hooks/            session start, commit gate
    gates/            executable gate scripts
    workflows/        review sweep, council
    evals/            cases.jsonl, rubric.md
    scripts/          run_evals.py
    pricing.yml
  docs/
```

## Adding a gate

See [gates.md](gates.md). Short version: an executable in `gates/` that exits 0 for pass,
non-zero for fail, and 78 for could-not-run. Register it under `gates:` in the config
schema.

Exit 78 is the one people get wrong. Use it whenever the tool is missing or the environment
cannot support the check. Never exit 0 in that case.

## Adding a skill

One directory under `skills/`, containing `SKILL.md` with frontmatter:

```yaml
---
name: your-skill
description: When to use it. Written so the model can match it against a task.
---
```

Rules:

1. Keep it short. A skill that runs past 150 lines is doing two jobs.
2. State the rule, then the exception. Not the other way round.
3. Give one concrete example per rule, not three.
4. Say what not to do, explicitly. Models need the negative case.
5. No preamble inside the skill body.

## Adding an agent

One file under `agents/`. An agent earns its place when it has a job no existing agent
does. Not when it would be nice to have a name for something.

Before adding one, check: does this differ from an existing agent in capability, or only in
prompt wording? If only in wording, extend the existing agent instead.

## Evals are required

Any change to a prompt, skill, or agent needs an eval run.

```
/hyperpower:eval
```

A change ships only when it has no blockers, correctness and safety are within 0.1 of
baseline or better, and the weighted score beats baseline.

Add a case for the behaviour you are fixing. A fix without a case will regress.

## Writing style

All documentation, agent output, commit messages, and skill files follow two rule sets.

### Structure

1. Lead with the action. First line is something the reader can do.
2. Number multi-step work. One bounded action per step.
3. Cap lists at five. If it grows past five, split into now versus later.
4. No preamble, no recap, no closing pleasantries.
5. Give specific time estimates. "About 15 minutes", not "some work".

### Voice

1. Short sentences. Subject, verb, object.
2. No idioms, no metaphors, no wordplay.
3. No rhetorical build-up and no rhetorical questions.
4. Technical terms stay exact. Plain English is for the glue between them.
5. State cause and fix for errors. Never "uh oh" or "there seems to be a problem".

Tables beat paragraphs when the content is a set of options or fields.

### What this rules out

Not this:

> Let's take a look at how the gate system works. You'll find that gates are essentially
> the beating heart of the harness, and getting them right is absolutely crucial.

This:

> Gates run commands and read exit codes. A gate that cannot run reports that it did not
> run. It never reports a pass it did not verify.

## Pull requests

1. One change per PR.
2. Include the eval output.
3. Say what you tested, and say plainly what you did not.

If a check was skipped, say so. A PR claiming verification it did not do is worse than one
that admits a gap.
