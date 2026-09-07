---
name: paths
description: Show or set paths.source in hyperpower.yml - the only directories the harness may edit. Everything else in the repo is read-only to it. Run /hyperpower:paths to show, or /hyperpower:paths src/ packages/core/src/ to replace the list.
---

# Paths

Show `paths.source`. Pass directories to replace it.

`paths.source` is the only list of directories the harness may edit. Everything else in the repo is read-only to it. Keep the list tight. A wide list is how generated code, vendored code, and lockfiles get edited by accident.

No `hyperpower.yml` at the repo root: print `No hyperpower.yml. Run /hyperpower:init.` and stop.

## Show

No arguments. Print all four path fields, the file each came from, and the tracked file count each `paths.source` entry covers.

```
paths.source  (hyperpower.yml)
  src/                  412 files
  packages/core/src/     88 files

paths.tests   [src/**/*.test.ts]   hyperpower.yml
paths.docs    [docs/]              hyperpower.yml
paths.ignore  [dist/, node_modules/]  hyperpower.yml
```

Counts come from `git ls-files` with `paths.ignore` excluded. An entry covering zero files is printed as `0 files - check this path`.

## Set

Arguments replace `paths.source` entirely. This is a replace, not an append.

```
/hyperpower:paths src/ packages/core/src/
```

Five steps:

1. Resolve each argument against the repo root.
2. Validate each argument against the rejection table below. One rejection stops the whole command. Write nothing.
3. Print the diff: old list, new list, and the file count for each entry.
4. Ask for confirmation. Wait for a yes.
5. Write `paths.source`. Change no other field.

Directories take a trailing slash. A glob is allowed: `packages/*/src/`. A single file is not; this field holds directories.

## Rejections

| Argument | Result |
|---|---|
| Path does not exist | reject. Print the path. |
| Path resolves outside the repo root | reject. Print the resolved path. |
| Path matches an entry in `paths.ignore` | reject. Print both entries. |
| `.`, `/`, or the repo root | reject. That grants edit access to `.git`, lockfiles, and CI config. |
| A file rather than a directory | reject. Print the parent directory as the suggestion. |

Reject before writing, never after. A partially applied list is worse than no change.

## Which file gets written

| State | Written to |
|---|---|
| `hyperpower.local.yml` already sets `paths.source` | `hyperpower.local.yml`. It overrides per field, so writing the committed file would have no effect. Say so in the output. |
| Otherwise | `hyperpower.yml` |

## Output after a write

Three lines. Nothing else.

```
paths.source updated in hyperpower.yml
  was  [src/]
  now  [src/, packages/core/src/]  500 files
```

## Do not

- Do not append to the list. Arguments replace it.
- Do not widen the list to clear a permission error. Narrow scope is the feature, not the obstacle.
- Do not add build output, vendored code, generated directories, or `node_modules/`.
- Do not write without printing the diff and getting a yes.
- Do not edit `paths.tests`, `paths.docs`, or `paths.ignore`. This command owns one field.
