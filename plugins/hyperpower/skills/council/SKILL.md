---
name: council
description: Put one question to the departments that own it and count independent votes. Each voice answers without seeing any other, then one agent synthesises. The cheap half of the swarm - for the back and forth where positions read and answer each other, use /hyperpower:standup instead. Use /hyperpower:council "<question>".
---

# council

Independent votes, one pass, one synthesis. No voice sees another.

That independence is the point. A voice that reads someone else's answer first anchors to
it, and you get agreement that looks like consensus and is actually contagion.

| | |
|---|---|
| `/hyperpower:council` | independent votes. Cheaper. The default. |
| `/hyperpower:standup` | voices read each other and respond in rounds. Roughly twice the cost. |

Use council when you want independent reads. Use standup when the answer turns on how two
concerns trade against each other and the positions need to actually meet.

Neither is for a decision a later commit can undo cheaply. One agent is enough there.

## Step 1 - pick the room

Read `${CLAUDE_PLUGIN_ROOT}/departments.yml`. Match the question against `attendance`, take
the departments it names, and take every voice in those departments.

Each department is a pair holding opposed priors on purpose. `be-architect` argues for data
that survives the third incident; `be-pragmatist` argues for the smallest correct thing.
Counting both is what makes the vote worth counting.

Two departments, four voices, is the normal size. Do not add a department because it might
have an opinion - it attends when the question would change its work.

`--full` uses `full_room`: twelve voices. Only when the human asks for it by name.

State the room before spawning:

```
Room  backend, infra. The question changes the schema and adds a dependency to operate.
      4 voices, 1 synthesis. ~5 calls.
```

## Step 2 - collect the votes

Spawn every voice **in parallel**, each with the question and nothing from any other voice.

Each returns the four-part shape its agent file specifies: position, because, cost of being
wrong, what would change my mind.

**A voice that fails to answer is reported, never dropped.** A missing vote silently
excluded from a tally makes the tally a lie. Say which voice did not answer and why.

## Step 3 - synthesise

One agent, judgment tier, given every vote:

1. **Where the room agreed.** Usually more than the disagreement suggests.
2. **Where it split**, and what the split actually turns on.
3. **A recommendation**, with the losing position stated fairly enough that the human can
   still choose it.
4. **What would settle it** - a measurement, a spike, or a question for a user.

A synthesis that reports agreement the room did not reach has destroyed what the council was
for. One voice standing against five is reported as exactly that, with its argument intact.

## Step 4 - the human decides

Report the synthesis. Do not act on it.

When the human accepts a recommendation, write a decision record into
`memory.decisions_dir` with `decided_by: agent_proposed_approved`, including the rejected
positions and why. `/hyperpower:decisions` reads that back when the question returns.

Do not write the record before the human decides. A recommendation is not a decision.

## Cost

| Room | Voices | Calls |
|---|---|---|
| one department | 2 | ~3 |
| two departments | 4 | ~5 |
| `--full` | 12 | ~13 |

Votes run on the mechanical tier. The synthesis runs on judgment - weighing twelve positions
against each other is the part that needs it.

## Do not

- Do not let any voice see another voice's answer. That is the whole basis of the method.
- Do not drop a voice that abstained or failed. Report it.
- Do not synthesise into false agreement.
- Do not run a council for a cheaply reversible decision.
- Do not write a decision record for a recommendation nobody accepted.
