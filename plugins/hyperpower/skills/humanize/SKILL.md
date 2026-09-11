---
name: humanize
description: Find the marks a model leaves on code and take them out. Three passes - slop code with a plan to fix it, slop comments lightened against this repo's own comment rule, and repeated code with a plan to collapse it. Runs with or without the static linters installed and says which. Use /hyperpower:humanize, or /hyperpower:humanize <path>, or --all for the whole repo.
---

# humanize

Three passes over code a model wrote. Each reports findings and proposes a plan. Only the
comment pass edits anything, and only after you say so.

| | |
|---|---|
| `/hyperpower:humanize` | standalone, self-sufficient. Type this one. |
| `/hyperpower:sweep` | runs inside a pipeline run, assumes the slop gate already ran |

`sweep` skips placeholders, stubs and clones because layer 1 owns them. When the static
tools are not installed, layer 1 never ran and those classes go unhunted. `humanize` checks
first and covers them itself.

## Scope

Default: the current diff against the default branch, plus uncommitted work. A path
argument narrows it. `--all` takes the repo and is slow on anything large.

Never scan `paths.ignore`, `paths.state`, or a vendored directory. Generated code is not
slop; it is generated.

## Step 0 - what tooling is here

```bash
command -v antislop ai-slop-detector jscpd
```

Say which are present in one line before starting. Two modes:

- **Tools present.** Run them first, take their findings as given, and spend the model pass
  on what they cannot decide.
- **Tools absent.** Say so plainly, then cover their classes yourself. Report that the
  findings are a model's reading rather than a linter's, because that is a weaker claim and
  the user should know which they are getting.

Never claim a class was checked by a tool that is not installed.

---

## Pass 1 - slop code

Nine classes. The first five are what static tools would catch; the last four are what they
cannot.

| Class | What it looks like |
|---|---|
| Placeholder | `TODO`, `FIXME`, `HACK`, `XXX` left behind |
| Deferral | "for now", "temporary", "in a real implementation", "you would" |
| Hedging | "hopefully", "should work", "assumes" in a comment or a name |
| Stub | empty function, `pass`, `NotImplementedError`, a return nobody reads |
| Dead path | a branch, export or import nothing reaches |
| Over-abstraction | a factory with one implementation, an interface with one implementer, a config object for two parameters |
| Wrong fit | works, but not how this repo does it. `CODEBASE_RULEBOOK.md` is the input |
| Defensive junk | try/except that swallows and returns a default nobody checks |
| Invented surface | a helper that exists because nobody looked for the existing one. Grep before claiming this |

For each finding: `file:line`, the class, one sentence on what is wrong, and **the specific
fix** — not "refactor this".

Then a plan, ordered by what bites first. Group findings that share a fix. Say which are
mechanical and which need a decision.

**Do not apply anything in this pass.** Propose. Nine findings in one diff usually means one
underlying cause, and fixing them one at a time fixes the wrong thing nine times.

---

## Pass 2 - slop comments

The only pass that edits, and only with a yes.

**Read the repo's own comment rule first**, in this order: `CODEBASE_RULEBOOK.md`, then
`CLAUDE.md`, then `.claude/rules/`. Enforce what you find there. Do not impose a rule the
repo has not stated — a house that wants docstrings everywhere is entitled to them.

With no stated rule, use this: a comment earns its place when it explains **why**. A comment
restating **what** the line does is noise.

Take out:

- Restatement — `// increment i`, `// set the user's name`
- A docstring repeating the signature and adding nothing
- Section banners inside a function short enough to read whole
- `// This function...` openers
- Commentary on the obvious — `// loop through the array`
- A comment that was true before the code changed. Worse than none.

Keep, always:

- Why a non-obvious choice was made
- A workaround, with what it works around
- A warning about an ordering, a race, or a footgun
- A link to an issue, a spec, or a decision record
- Anything the repo's own rule says to keep

Report the count and a sample first. Then ask. Then apply.

Never delete a comment you cannot replace with certainty that it says nothing. When in
doubt, list it and leave it.

---

## Pass 3 - repeated code

Repetition is evidence, not a verdict. Three copies of six lines may be correct; the
abstraction that unifies them may cost more than the duplication.

Find:

- Blocks of five or more lines appearing three or more times
- The same conditional shape repeated with different values
- Parallel functions differing only in a type or a field name
- Copy-paste with one edit, which is where bugs live — the edit that was missed

For each: every location, what actually differs, and a proposed collapse.

Then judge it, and say which you are recommending:

| Verdict | When |
|---|---|
| Collapse it | the copies change together, and one of them has already drifted |
| Leave it | the copies belong to different domains and will diverge further |
| Leave it for now | two copies. Three is the threshold; two is a coincidence |

A plan that collapses everything repeated is how a codebase gets a utility module nobody
can read. Recommend leaving things alone when that is right.

---

## Output

```
humanize  12 files in the diff
  tooling  antislop absent, ai-slop-detector absent. Model pass only.

Pass 1  slop code           7 findings, 3 mechanical
Pass 2  slop comments      23 candidates, 4 to keep
Pass 3  repeated code       2 clusters, 1 worth collapsing

Worst first
  1  src/settings/Panel.tsx:34   swallowed exception returns [] — a failed
     fetch is indistinguishable from no results
  2  src/settings/Panel.tsx:71   ...
```

Lead with the finding that would bite first, not with pass 1 because it is pass 1.

Say plainly when a pass found nothing. A clean pass is a result.

## Do not

- Do not apply pass 1 or pass 3. They propose.
- Do not edit comments before showing a sample and getting a yes.
- Do not delete a comment explaining why.
- Do not claim a static tool ran when it is not installed.
- Do not report the same finding in two passes. A repeated block full of restating comments
  belongs in pass 3, once.
- Do not recommend collapsing two copies of anything.
- Do not touch generated code, vendored directories, or `paths.state`.
