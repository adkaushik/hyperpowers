---
name: standup
description: Put a question to the department that owns it and let the two voices argue in rounds - each reads the other's position and responds before you get a synthesis. The expensive one. Use /hyperpower:standup "<question>", or add --full for every department. For independent votes without the back and forth, use /hyperpower:council instead.
---

# standup

A round-based debate. Each voice reads what the other said and responds, twice, then one
synthesis. That is the difference from `council`, where voices never see each other.

**This is the most expensive call in the harness.** Two rounds double the voice count, and
`--full` puts twelve voices in the room. Do not reach for it by default.

| Use | For |
|---|---|
| `/hyperpower:council` | independent votes, one pass, cheaper. The default. |
| `/hyperpower:standup` | the positions need to meet. A tradeoff nobody has resolved. |

Reach for standup when the answer depends on how two concerns trade against each other -
correctness against speed, spend against safety, scope against evidence. Reach for council
when you want independent reads and expect them to mostly agree.

## Step 1 - pick the room

Read `${CLAUDE_PLUGIN_ROOT}/departments.yml`. Match the question against `attendance` and
take the departments it names. Two departments is four voices, which is the normal size.

`--full` uses `full_room`: six departments, twelve voices. Only when the human asks for it
by name. Say what it will cost before starting.

Name the room and why before spawning anything:

```
Room  backend, infra. The question is about where limiter state lives, which changes
      the schema and adds a dependency to operate.
      4 voices, 2 rounds, 1 synthesis. ~9 calls.
```

## Step 2 - round one, independent

Spawn every voice in the room **in parallel**, each with the question and nothing from any
other voice. Round one must be independent, or the first voice to answer anchors the rest.

Each returns the four-part shape its agent file specifies: position, because, cost of being
wrong, what would change my mind.

## Step 3 - round two, they read each other

Spawn each voice again. Give it every round-one position **except a restatement of its
own**, and this instruction:

> Here is what the room said. Respond to the strongest argument against your position, not
> the weakest. If something changes your position, say which part and why. If nothing does,
> say that and say what the other side is missing.
>
> Do not converge to be agreeable. A room that agrees after one round has learned nothing,
> and the synthesis needs the disagreement to weigh.

Two rounds. Not three. A third round produces restatement, and the token cost is real.

## Step 4 - synthesise

One agent, judgment tier. Give it every position from both rounds and this job:

1. **What the room agreed on.** Often more than it looks like from the argument.
2. **What it did not**, and what the disagreement actually turns on. Name the tradeoff.
3. **A recommendation**, with the losing argument stated fairly enough that the human can
   still pick it.
4. **What would settle it** - the measurement, the spike, or the question for a user.

A synthesis that hides the disagreement has destroyed the thing the standup was for. If a
voice stood alone against five, say so and say why it might still be right.

## Step 5 - record it

A standup answers a question expensive enough to be worth asking. Write a decision record
into `memory.decisions_dir` with `decided_by: agent_proposed_approved` once the human picks,
including the rejected positions and why. That is what `/hyperpower:decisions` reads back
when this comes up again in four months.

Do not write the record before the human has decided. A recommendation is not a decision.

## Cost

Say this before starting, not after:

| Room | Voices | Calls |
|---|---|---|
| one department | 2 | ~5 |
| two departments | 4 | ~9 |
| `--full` | 12 | ~25 |

Round-one voices run on the mechanical tier. Round two and the synthesis run on judgment -
that is where reading another position and weighing it actually happens.

## Do not

- Do not run standup for a question a later commit can undo cheaply. One agent is enough there.
- Do not let round one see any other voice. That is the whole basis of the exercise.
- Do not run a third round.
- Do not put a department in the room because it might have an opinion. It attends when the
  question would change its work.
- Do not synthesise into false agreement. Report the split.
- Do not write a decision record for a recommendation the human has not accepted.
