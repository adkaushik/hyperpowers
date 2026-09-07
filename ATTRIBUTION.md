# Attribution

hyperpower builds on work by other people. All of it is MIT licensed.

## Superpowers

Process skills: test-driven development, brainstorming, systematic debugging, writing
plans, using git worktrees, verification before completion, requesting and receiving code
review.

- Project: https://github.com/obra/superpowers
- Author: Jesse Vincent
- Licence: MIT

Skills vendored from Superpowers carry a note at the top of the file saying so.

## superflow

Ideas taken and adapted:

- Typed handoff contracts between stages, so a handoff fails loudly instead of degrading
  into lossy prose
- The bounded fix loop with model escalation across rounds
- The review shape: partition a diff into slices, review each, then send a dedicated
  skeptic at every finding
- The rulebook: a generated per-repo conventions file that lets generic agents conform to
  a specific codebase

- Project: https://github.com/cashwanikumar/superflow
- Author: Ashwani Kumar
- Licence: MIT

## i-have-adhd

The output shaping rules used in the render layer, and the shape of the eval runner: blind
A/B/C labelling, a weighted rubric, paired-row enforcement, and a release gate.

- Author: https://github.com/ayghri
- Licence: MIT

## antislop

The static slop linter run in the gate. Detects placeholders, deferrals, hedging, stubs,
and redundant comments left behind by code generation.

- Project: https://github.com/skew202/antislop
- Licence: see that repository

## ai-slop-detector

Additional static checks run alongside antislop: unresolved imports, dead pipelines,
copy-paste clones, buzzword-padded documentation.

- Project: https://github.com/flamehaven01/ai-slop-detector
- Licence: see that repository

## What is original here

Gates that execute commands and fail closed. The durable run journal with drift-checked
resume. The assumption lifecycle. The split between a capped hot rulebook and an unbounded
cold decision archive, with a threshold-driven promotion path between them. The five
background agents. Detection-driven per-repo setup. Local usage and cost analytics.
