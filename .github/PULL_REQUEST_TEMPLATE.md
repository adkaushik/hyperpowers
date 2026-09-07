## What changed

One sentence. One change per PR. A PR carrying two unrelated changes gets split before
review.

## Why

The problem this fixes. Link the run id, issue, or decision record if one exists.

## Eval output

Required for any change to a prompt, skill, or agent. Paste the verdict block from
`/hyperpower:eval`. Paste it whole. Do not summarise it, and do not paste the score alone.

```
paste the verdict block here
```

A change ships only when it has no blockers, correctness and safety are within 0.1 of
baseline or better, and the weighted score beats baseline.

Add a case for the behaviour you are fixing. A fix without a case will regress.

Not a prompt change? Write `not a prompt change` above and delete the block.

## Tested

The commands you ran and what each one proved. Commands, not adjectives.

- [ ] `python3 plugins/hyperpower/scripts/hp-selfcheck` exits 0
- [ ] `python3 scripts/run_evals.py validate` exits 0, run from `plugins/hyperpower/`
- [ ] Added or updated an eval case, when this changes a prompt, skill, or agent

## Not tested

Say plainly what you did not check. Every PR has something here.

Examples: ran on macOS only, did not exercise the browser gate, did not run against a
monorepo, did not test the resume path with a drifted tree.

A PR claiming verification it did not do is worse than one that admits a gap. Do not write
`n/a` here unless you ran every gate on every supported stack.
