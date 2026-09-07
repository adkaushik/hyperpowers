---
name: sweep
description: Layer 2 slop sweep on the current diff - the model pass for what static analysis cannot see. Finds over-abstraction, wrong-fit code, swallowed exceptions, comments explaining what instead of why, and invented helpers that duplicate an existing one. Corrects them, re-runs the static slop gate, and stops after two passes. Use /hyperpower:sweep.
---

# Sweep

Read the current diff. Find the five slop classes static analysis cannot see. Correct them. Re-run the static gate. Stop after two passes.

About three minutes on a ten-file diff.

This is layer 2. Layer 1 is `antislop` plus `ai-slop-detector`. It already ran in the slop gate and it owns placeholders, deferrals, hedging, stubs, redundant comment text, unresolved imports, dead pipelines, and clones. Do not hunt those again. Hunt what a static tool cannot decide.

## Profile

| Layer | Where it runs | Profile |
|---|---|---|
| 1 | the slop gate, every run | `gates.slop.profile`, `core` by default |
| 2 | this skill | `standard` |
| any | anywhere | never `strict` |

Run `antislop --profile standard` over the changed files first, for hints. Never pass `--profile strict`. Strict fights the codebase, and its findings are style opinions this repo did not ask for.

## Step 1 - load the inputs

1. Diff: `git diff --name-only $(git merge-base HEAD origin/<default-branch>)`, plus `git status --porcelain` for uncommitted work.
2. Config: `hyperpower.yml`, then `hyperpower.local.yml` over it, field by field.
3. Rulebook: `CODEBASE_RULEBOOK.md` at the repo root.

| Config field | Used for | If absent |
|---|---|---|
| `paths.source` | the only files this skill may edit | edit only files the diff already touched |
| `paths.ignore` | skip generated and vendored files | skip nothing |
| `gates.slop.profile` | the profile the layer 1 re-run uses | `core` |
| `limits.fix_loop_max_rounds` | quoted in the handoff, not enforced here | say nothing about rounds |

No `hyperpower.yml`: sweep the diff with the defaults above. Do not ask the user to create one.

No `CODEBASE_RULEBOOK.md`: skip the `wrong_fit` class entirely and say so in the report. Do not substitute your own taste for a rule this repo never wrote down.

## Step 2 - hunt the five classes

Read every changed file in full. A hunk hides its own context.

| Class | Signal in the diff | Correction |
|---|---|---|
| `over_abstraction` | a factory, interface, base class, or strategy map with exactly one implementation | inline it into its single caller |
| `wrong_fit` | works, but not the pattern a rulebook rule names | rewrite it to the named pattern |
| `defensive_junk` | a caught exception returning a default no caller checks | let it propagate, or return an error the caller handles |
| `what_comment` | a comment restating the line under it | delete it, or replace it with the reason |
| `invented_api` | a new helper that duplicates one already in the tree | delete it and call the existing one |

Every correction cites `file:line`. An `invented_api` correction cites two: the new helper, and the existing one it duplicates. No citation, no correction.

Search before calling something invented. Run `rg` on the function name, then on the signature, then on the call sites. A helper you did not find is not a helper that does not exist.

## Step 3 - the exceptions

Leave the code alone when the line below holds. State the exception in the report. Never correct past one silently.

| Class | Leave it when |
|---|---|
| `over_abstraction` | a second implementation exists in the tests, or the type is exported from a published package API |
| `wrong_fit` | no rulebook rule covers the pattern. Taste is not a rule. |
| `defensive_junk` | the catch sits at a process boundary and logs, or a rulebook rule requires it |
| `what_comment` | the comment names a non-obvious constraint, or it documents a public symbol |
| `invented_api` | the existing helper is outside `paths.source`, or a rulebook rule deprecates it |

## Step 4 - correct, then re-run layer 1

One pass is: apply the corrections, then re-run layer 1 on the changed files.

1. Apply the corrections. Edit only files inside `paths.source` that the diff already touched.
2. Re-run layer 1: `antislop --profile <gates.slop.profile>` and `ai-slop-detector` on those files.
3. Layer 1 passes: stop, report, exit.
4. Layer 1 fails: run pass 2 on what it flagged, and nothing else.
5. Layer 1 fails after pass 2: stop. Every remaining item goes to the fix loop.

Two passes maximum. There is no third pass. Unbounded polish is the failure mode of this skill: each pass rewrites working code, every rewrite gives the next pass something new to flag, and the loop has no natural end.

A tool that is not on PATH did not run. Report it as did not run, never as a pass, and print `/hyperpower:doctor` as the fix.

## Step 5 - hand off what survived

Each item that survives two passes becomes one finding, in the reviewer's finding shape with this skill's five classes in `class`.

```json
{"id":"s1","class":"over_abstraction","file":"src/api/client.ts","line":18,
 "claim":"ClientFactory has one implementation and one caller",
 "failure_scenario":"a second backend needs a client; the factory is edited instead of the caller, and both paths drift",
 "evidence":["src/api/client.ts:18","src/api/index.ts:4"],
 "severity":"low","status":"unverified"}
```

`failure_scenario` is required, as it is for a reviewer finding. No scenario, no finding. `class` here is one of the five above, never one of the reviewer's five.

The fix loop treats it as a normal finding and is bounded by `limits.fix_loop_max_rounds`. Sweep does not run again inside that loop.

## Output

Four blocks, in this order. Skip an empty block rather than printing a header with nothing under it.

1. **Corrected** - class, `file:line`, one line each.
2. **Left alone** - class, `file:line`, which exception applied.
3. **Passes** - 1 or 2, and the layer 1 result after each.
4. **To the fix loop** - count first, then the findings.

Rank, never cap. Show five per block, then say how many remain. The full list stays in the contract.

## Do not

- Do not run a third pass, and do not sweep your own corrections a second time.
- Do not pass `--profile strict`, and do not offer it as an option.
- Do not edit a file the diff did not touch, or any file outside `paths.source`.
- Do not rename, reformat, or reorder code for readability. The lint gate owns that.
- Do not delete an abstraction that has a second implementer, including one in a test.
