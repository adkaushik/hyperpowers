export const meta = {
  name: 'hyperpower-review-sweep',
  description: 'Partition a diff into slices, run one reviewer per slice, then run one skeptic per deduped finding.',
  whenToUse:
    'Before merging a change that spans more than one file or more than one subsystem. Skip it for a one-file change with a rulebook precedent — a single reviewer costs less and finds the same defects.',
  phases: [
    { title: 'Partition', detail: 'One mechanical agent groups the diff into 2-6 slices and attaches each blast radius' },
    { title: 'Sweep', detail: 'One hyperpower reviewer per slice, in parallel' },
    { title: 'Verify', detail: 'One hyperpower skeptic per deduped finding' },
  ],
}

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

const a = args && typeof args === 'object' ? args : {}
const base = typeof a.base === 'string' && a.base.trim() ? a.base.trim() : 'main'
const note = typeof a.note === 'string' ? a.note.trim() : ''
const scope = normalizeScope(a.scope)

function normalizeScope(value) {
  if (Array.isArray(value)) {
    const list = value.filter((p) => typeof p === 'string' && p.trim()).map((p) => p.trim())
    return list.length ? list : null
  }
  if (typeof value === 'string' && value.trim()) return [value.trim()]
  return null
}

// Files the partition stage returned inside an unusable slice. They are folded
// into left_out so a malformed slice never reads as reviewed code.
const partitionRejects = []

// ---------------------------------------------------------------------------
// Roles
//
// One spelling: the plugin namespace plus the bare `name` in agents/<role>.md.
// If it does not resolve, fall back to an inline role brief. The fallback is
// logged. A silent fallback would report a persona review that never ran.
// A bare `reviewer` is never tried: it would resolve to a same-named agent in
// the user's own ~/.claude/agents/ and return a contract this script cannot read.
// ---------------------------------------------------------------------------

const ROLES = {
  reviewer: {
    agentTypes: ['hyperpower:reviewer'],
    brief: [
      'Act as the hyperpower reviewer. You are read-only. You describe defects and never fix them.',
      'Hunt five classes: logic, edge_case, regression, integration_seam, rulebook_deviation.',
      'Every finding carries a file:line anchor and a concrete failure scenario. No anchor, no finding.',
      'Second job: extract assumptions the diff depends on that nothing in the slice establishes. Report them with class undeclared_assumption.',
      'An empty findings list is a valid answer. Do not pad it. Every padded finding costs a whole skeptic.',
      'Do not report style, naming, or formatting. Do not assign a verdict. Do not edit any file.',
    ].join('\n'),
  },
  skeptic: {
    agentTypes: ['hyperpower:skeptic'],
    brief: [
      'Act as the hyperpower skeptic. You are read-only. You verify exactly one finding.',
      'Refute first, trace second. Reversing that order produces confirmation bias.',
      'CONFIRMED means you traced the defect from an entry point to the wrong result, with a file:line at each hop.',
      'REFUTED means you found the guard, type, or unreachability that makes the failure impossible on every path. Cite it.',
      'PLAUSIBLE means the code alone cannot settle it. Name what is undecidable and where you looked.',
      'Never refute because no reproduction exists, because tests pass, because it is unlikely, because a comment claims it is handled, or because it has not failed yet.',
    ].join('\n'),
  },
}

async function spawn(role, prompt, opts) {
  const role_def = ROLES[role]
  for (const type of role_def.agentTypes) {
    try {
      return await agent(prompt, Object.assign({}, opts, { agentType: type }))
    } catch (err) {
      continue
    }
  }
  log(`${role}: no registered agent type resolved. Running the inline role brief instead.`)
  return await agent(`${role_def.brief}\n\n${prompt}`, opts)
}

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

const PARTITION_SCHEMA = {
  type: 'object',
  properties: {
    empty_diff: { type: 'boolean' },
    base_sha: { type: 'string' },
    partitions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          slice_id: { type: 'string' },
          title: { type: 'string' },
          rationale: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          blast_radius: { type: 'array', items: { type: 'string' } },
        },
        required: ['slice_id', 'title', 'rationale', 'files', 'blast_radius'],
      },
    },
    left_out: {
      type: 'array',
      items: {
        type: 'object',
        properties: { path: { type: 'string' }, reason: { type: 'string' } },
        required: ['path', 'reason'],
      },
    },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['empty_diff', 'base_sha', 'partitions', 'left_out', 'notes'],
}

const SLICE_SCHEMA = {
  type: 'object',
  properties: {
    slice_id: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          class: {
            type: 'string',
            enum: ['logic', 'edge_case', 'regression', 'integration_seam', 'rulebook_deviation', 'undeclared_assumption'],
          },
          file: { type: 'string' },
          line: { type: 'integer' },
          claim: { type: 'string' },
          failure_scenario: { type: 'string' },
          evidence: { type: 'array', items: { type: 'string' } },
          checkable: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['id', 'class', 'file', 'line', 'claim', 'failure_scenario', 'evidence', 'severity'],
      },
    },
    out_of_scope: { type: 'array', items: { type: 'string' } },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['slice_id', 'findings', 'out_of_scope', 'notes'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    finding_id: { type: 'string' },
    verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'PLAUSIBLE'] },
    trace: { type: 'array', items: { type: 'string' } },
    refutation_attempted: { type: 'string' },
    undecidable: { type: 'string' },
    severity: { type: 'string', enum: ['high', 'medium', 'low'] },
    collateral: { type: 'array', items: { type: 'string' } },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['finding_id', 'verdict', 'refutation_attempted', 'severity'],
}

// ---------------------------------------------------------------------------
// Shared prompt fragments
// ---------------------------------------------------------------------------

const CONFIG_BLOCK = [
  'Config. Read hyperpower.yml at the repo root, then hyperpower.local.yml over it, field by field.',
  'If neither file exists, use the fallback stated for each field and do not ask anyone to create one.',
].join('\n')

const IGNORE_FALLBACK = [
  'node_modules/, vendor/, third_party/',
  'dist/, build/, out/, target/, .next/, .nuxt/, coverage/',
  'generated/, __generated__/, any path containing .generated. or .pb. or _pb2',
  '.venv/, site-packages/, __pycache__/',
  'lockfiles: pnpm-lock.yaml, package-lock.json, yarn.lock, bun.lockb, uv.lock, poetry.lock, go.sum, Cargo.lock, Gemfile.lock',
  'minified and binary: *.min.js, *.map, *.snap, *.png, *.jpg, *.pdf, *.woff2',
].join('\n  - ')

const NO_RENDER_RULES = [
  'Do not apply the cap-at-five rule and do not apply ADHD shaping. This is an agent-to-agent handoff.',
  'Capping a list before the render boundary silently drops defects. Rank the list. Never truncate it.',
].join(' ')

const changeSetBlock = scope
  ? [
      'Change set. A scope override was supplied. Review exactly these paths and ignore the diff:',
      scope.map((p) => `  - ${p}`).join('\n'),
      'Run "git diff HEAD -- <path>" per path for context. If a path has no diff, it is a post-fix re-run target: read the file as it stands.',
      'Set empty_diff to true only when every supplied path is missing from the working tree.',
    ].join('\n')
  : [
      'Change set. Run these two commands:',
      `  1. git diff ${base}...HEAD --name-status`,
      '  2. git status --porcelain',
      `Take committed changes from the first and uncommitted changes from the second. Record the merge base with "git merge-base ${base} HEAD" and return it as base_sha.`,
      `If ${base} does not resolve, fall back to "git diff HEAD --name-status", return base_sha as "HEAD", and say so in notes.`,
      'Set empty_diff to true when both commands report zero changed paths.',
    ].join('\n')

const noteBlock = note ? `\nCaller note, for context only: ${note}\n` : ''

// ---------------------------------------------------------------------------
// Phase 1 — Partition
// ---------------------------------------------------------------------------

phase('Partition')
log(scope ? `Partition: scope override, ${scope.length} path(s).` : `Partition: git diff ${base}...HEAD`)

const partitionPrompt = [
  'You are the partition stage of a review sweep. You are read-only. Do not edit, create, or delete any file.',
  '',
  CONFIG_BLOCK,
  'Use paths.ignore to decide what to skip. Fallback when the config is absent:',
  `  - ${IGNORE_FALLBACK}`,
  '',
  changeSetBlock,
  noteBlock,
  'Steps.',
  '1. Read the config, then get the change set.',
  '2. Filter. Drop generated, vendored, minified, lockfile, and binary paths. Every dropped path goes into left_out with a one-line reason. Never drop a path silently.',
  '3. Group the surviving files into slices. Files belong in the same slice when they share a module, a route, a data shape, or a call edge. Split two groups apart when no call edge runs between them.',
  '4. For each slice, find the blast radius: files OUTSIDE the slice that call or depend on the changed code. Find them by grepping for the exported symbol names the slice changed. List at most 12 per slice, most-coupled first.',
  '5. Give each slice a slice_id of s1, s2, s3 and so on, a one-line title, and a one-line rationale naming what holds it together.',
  '',
  'The count rule. Return 2 to 6 slices.',
  'The exception. Return exactly 1 slice when fewer than two files survive filtering, or when every surviving file sits in one module and the whole change is under roughly 150 changed lines.',
  'If you find more than 6 coherent groups, merge the smallest until 6 remain and record each merge in notes.',
  '',
  'Every surviving file appears in exactly one slice. A file in two slices means two reviewers report the same defect and two skeptics get paid to verify it.',
  '',
  'Do not review the code. Do not report defects. Do not read file contents beyond what grouping and blast radius need.',
  NO_RENDER_RULES,
].join('\n')

const part = await agent(partitionPrompt, {
  label: 'partition diff',
  phase: 'Partition',
  schema: PARTITION_SCHEMA,
  // Partitioning is a mechanical stage. The script cannot read hyperpower.yml
  // to pick models.mechanical, so effort carries the tier signal instead.
  effort: 'low',
})

if (!part) {
  log('Partition returned nothing. No slice was reviewed.')
  return emptyResult('partition_failed', [], [], ['The partition agent returned no result. Re-run the sweep.'])
}

if (part.empty_diff) {
  log('Empty diff. Nothing to review.')
  return emptyResult('empty_diff', [], part.left_out || [], part.notes || [])
}

const slices = mergeOverflow(Array.isArray(part.partitions) ? part.partitions : [])
const leftOut = (Array.isArray(part.left_out) ? part.left_out.slice() : []).concat(partitionRejects)
const notes = Array.isArray(part.notes) ? part.notes.slice() : []
const baseSha = typeof part.base_sha === 'string' && part.base_sha ? part.base_sha : base

if (!slices.length) {
  log(`Nothing to review. ${leftOut.length} path(s) were filtered out.`)
  return emptyResult('nothing_to_review', [], leftOut, notes)
}

if (leftOut.length) log(`Left out of the sweep: ${leftOut.length} path(s). See left_out.`)
log(`${slices.length} slice(s): ${slices.map((s) => `${s.slice_id} (${s.files.length} files)`).join(', ')}`)

// ---------------------------------------------------------------------------
// Phase 2 — Sweep
//
// parallel(), not pipeline(), and that is deliberate. The dedupe below needs
// every slice's findings at once, so this is a real barrier: wall-clock here is
// the slowest slice, and the sweep tail is paid before any skeptic starts.
// It is paid on purpose. A duplicate finding costs a whole skeptic, and two
// reviewers reporting the same integration seam from opposite sides is the
// normal case in a partitioned review, not the rare one.
// Everywhere else uses pipeline(), so wall-clock is the slowest single chain
// rather than the sum of the slowest stages.
// ---------------------------------------------------------------------------

phase('Sweep')

const sliceFiles = {}
for (const s of slices) sliceFiles[s.slice_id] = s.files

const sweepRaw = await parallel(
  slices.map((s) => () =>
    spawn('reviewer', reviewerPrompt(s), {
      label: `review ${s.slice_id}: ${s.title}`,
      phase: 'Sweep',
      schema: SLICE_SCHEMA,
    })
  )
)

const missedSlices = slices.filter((s, i) => !sweepRaw[i])
if (missedSlices.length) {
  const ids = missedSlices.map((s) => s.slice_id).join(', ')
  log(`Sweep: ${missedSlices.length} slice(s) returned nothing and were NOT reviewed: ${ids}`)
  notes.push(`Slices not reviewed, agent returned no result: ${ids}`)
}

const outOfScope = []
const rawFindings = []
sweepRaw.forEach((res, i) => {
  if (!res) return
  const sliceId = res.slice_id || slices[i].slice_id
  for (const n of res.notes || []) notes.push(`${sliceId}: ${n}`)
  for (const o of res.out_of_scope || []) outOfScope.push(`${sliceId}: ${o}`)
  for (const f of res.findings || []) rawFindings.push(Object.assign({}, f, { slice_id: sliceId }))
})

// The barrier's whole purpose: one key per defect across every slice.
const deduped = dedupe(rawFindings)
const droppedDupes = rawFindings.length - deduped.length
log(`Sweep: ${rawFindings.length} finding(s), ${deduped.length} after dedupe by file:line:summary.`)
if (droppedDupes > 0) notes.push(`${droppedDupes} duplicate finding(s) merged before verification.`)

if (!deduped.length) {
  log('No findings. No skeptic was spawned.')
  return emptyResult('no_findings', slices, leftOut, notes, outOfScope)
}

// ---------------------------------------------------------------------------
// Phase 3 — Verify
//
// pipeline(), not parallel(). Each finding runs adjudicate then merge on its
// own clock. No finding waits for another finding's skeptic to land.
// ---------------------------------------------------------------------------

phase('Verify')
log(`Verify: one skeptic per finding, ${deduped.length} total.`)

const verifiedRaw = await pipeline(
  deduped,
  (finding) =>
    spawn('skeptic', skepticPrompt(finding), {
      label: `verify ${finding.file}:${finding.line}`,
      phase: 'Verify',
      schema: VERDICT_SCHEMA,
    }),
  (verdict, finding) => merge(finding, verdict)
)

// A stage that throws drops its item to null and skips the rest of the chain.
// Recover those as UNVERIFIED rather than losing the finding.
const verified = verifiedRaw.map((r, i) => r || merge(deduped[i], null))

const confirmed = verified.filter((f) => f.verdict === 'CONFIRMED').sort(bySeverity)
const plausible = verified.filter((f) => f.verdict === 'PLAUSIBLE').sort(bySeverity)
const refuted = verified.filter((f) => f.verdict === 'REFUTED')
const unverified = verified.filter((f) => f.verdict === 'UNVERIFIED').sort(bySeverity)

const collateral = []
for (const f of verified) for (const c of f.collateral || []) collateral.push(`${f.file}:${f.line} -> ${c}`)

log(
  `Verify: ${confirmed.length} CONFIRMED, ${plausible.length} PLAUSIBLE, ${refuted.length} REFUTED, ${unverified.length} UNVERIFIED.`
)

return {
  status: 'reviewed',
  confirmed,
  plausible,
  refuted_count: refuted.length,
  unverified_count: unverified.length,
  partitions: slices,
  unverified,
  left_out: leftOut,
  out_of_scope: outOfScope,
  collateral,
  notes,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function reviewerPrompt(slice) {
  const contract = {
    run_id: null,
    slice_id: slice.slice_id,
    files: slice.files,
    base_sha: baseSha,
    blast_radius: slice.blast_radius || [],
    assumptions: [],
  }
  return [
    'Review one slice of a partitioned diff. Report defects and undeclared assumptions.',
    '',
    'Input contract:',
    JSON.stringify(contract, null, 2),
    '',
    'run_id is null. There is no run journal for this sweep. Do not look for one and do not write one.',
    'assumptions is empty. Nothing upstream declared any. Treat every assumption you find as undeclared.',
    `Slice title: ${slice.title}`,
    `Why these files are one slice: ${slice.rationale || 'grouped by the partition stage'}`,
    noteBlock,
    CONFIG_BLOCK,
    'Fields used: paths.ignore to skip generated and vendored files, paths.tests to tell tests from source.',
    'Fallback when the config is absent: review every file in the contract, and treat a file as a test when its path says so.',
    '',
    `Get your diff with: git diff ${baseSha} -- <files>`,
    `If ${baseSha} does not resolve, use "git diff HEAD -- <files>" and record that in notes.`,
    'Read each changed file in full, not just the hunk. Then read the blast radius files that call the changed code.',
    '',
    'Read the other side of every integration seam even when it sits in another slice. Report defects there in out_of_scope, never in findings.',
    'Every finding needs a file:line anchor and concrete inputs or state that produce the wrong result. No anchor, no finding.',
    'Return zero findings when the slice is clean. That is a valid answer.',
    NO_RENDER_RULES,
  ].join('\n')
}

function skepticPrompt(finding) {
  const contract = {
    run_id: null,
    finding: {
      id: finding.id,
      slice_id: finding.slice_id,
      class: finding.class,
      file: finding.file,
      line: finding.line,
      claim: finding.claim,
      failure_scenario: finding.failure_scenario,
      evidence: finding.evidence || [],
      checkable: finding.checkable || '',
      severity: finding.severity,
      status: 'unverified',
    },
    base_sha: baseSha,
    slice_files: sliceFiles[finding.slice_id] || [],
  }
  return [
    'Verify exactly one finding. Try to prove it wrong by reading the code. Return one verdict.',
    '',
    'Input contract:',
    JSON.stringify(contract, null, 2),
    '',
    'run_id is null. There is no run journal. Do not look for one and do not write one.',
    finding.also_reported_by && finding.also_reported_by.length
      ? `This finding was reported independently by slices: ${finding.also_reported_by.join(', ')}. Independent agreement is not evidence. Verify the claim on its own.`
      : '',
    noteBlock,
    CONFIG_BLOCK,
    'Fields used: paths.source for where the implementation lives, paths.ignore to skip generated copies.',
    'Fallback when the config is absent: search the whole tree except .git.',
    '',
    'Set finding_id to ' + JSON.stringify(finding.id) + ' exactly.',
    'Refute first, trace second.',
    'CONFIRMED requires a trace from an entry point to the wrong result, one file:line per hop.',
    'REFUTED requires the line that makes the failure impossible on every path, and why it covers every caller.',
    'PLAUSIBLE requires naming what is undecidable from the code alone, and where you looked for it.',
    'refutation_attempted is required on every verdict. Say what you searched for and did not find.',
    '',
    'Never refute for lack of a reproduction. That rule has no exception.',
    'Never refute because tests pass, because the path is unlikely, because a comment claims it is handled, or because it has not failed yet.',
    NO_RENDER_RULES,
  ]
    .filter(Boolean)
    .join('\n')
}

function normalizeClaim(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .slice(0, 80)
}

function dedupe(findings) {
  const byKey = new Map()
  for (const f of findings) {
    const key = `${f.file}:${f.line}:${normalizeClaim(f.claim)}`
    const seen = byKey.get(key)
    if (!seen) {
      // Copy evidence rather than aliasing it. A missing array here would throw
      // below and take the whole sweep down after every reviewer was paid for.
      const evidence = Array.isArray(f.evidence) ? f.evidence.slice() : []
      byKey.set(key, Object.assign({}, f, { evidence, dedupe_key: key, also_reported_by: [] }))
      continue
    }
    if (f.slice_id && f.slice_id !== seen.slice_id && !seen.also_reported_by.includes(f.slice_id)) {
      seen.also_reported_by.push(f.slice_id)
    }
    for (const e of f.evidence || []) if (!seen.evidence.includes(e)) seen.evidence.push(e)
    if (rankSeverity(f.severity) > rankSeverity(seen.severity)) seen.severity = f.severity
  }
  return Array.from(byKey.values())
}

function merge(finding, verdict) {
  if (!verdict) {
    return Object.assign({}, finding, {
      verdict: 'UNVERIFIED',
      trace: [],
      refutation_attempted: '',
      undecidable: 'The skeptic returned no result. This finding was never adjudicated.',
      collateral: [],
      skeptic_notes: [],
    })
  }
  return Object.assign({}, finding, {
    verdict: verdict.verdict,
    trace: verdict.trace || [],
    refutation_attempted: verdict.refutation_attempted || '',
    undecidable: verdict.undecidable || '',
    severity: verdict.severity || finding.severity,
    reviewer_severity: finding.severity,
    collateral: verdict.collateral || [],
    skeptic_notes: verdict.notes || [],
  })
}

function rankSeverity(s) {
  if (s === 'high') return 3
  if (s === 'medium') return 2
  return 1
}

function bySeverity(x, y) {
  return rankSeverity(y.severity) - rankSeverity(x.severity)
}

function mergeOverflow(partitions) {
  const clean = []
  for (const p of partitions) {
    if (p && p.slice_id && Array.isArray(p.files) && p.files.length) {
      clean.push(p)
      continue
    }
    const files = p && Array.isArray(p.files) ? p.files.filter((f) => typeof f === 'string' && f) : []
    const id = (p && p.slice_id) || 'an unnamed slice'
    if (!files.length) {
      log(`Partition: ${id} carried no files. Nothing was dropped.`)
      continue
    }
    const reason = `Partition returned ${id} without a usable slice_id. The file was not reviewed.`
    for (const f of files) partitionRejects.push({ path: f, reason })
    log(`Partition: ${id} was malformed. Its ${files.length} file(s) were NOT reviewed. See left_out.`)
  }
  if (clean.length <= 6) return clean
  const kept = clean.slice(0, 5)
  const rest = clean.slice(5)
  const files = []
  const blast = []
  for (const p of rest) {
    for (const f of p.files) if (!files.includes(f)) files.push(f)
    for (const b of p.blast_radius || []) if (!blast.includes(b)) blast.push(b)
  }
  kept.push({
    slice_id: 's6',
    title: 'Merged remainder',
    rationale: `Partition returned ${clean.length} slices. Slices 6 and above were merged to hold the sweep at six reviewers.`,
    files,
    blast_radius: blast,
  })
  log(`Partition returned ${clean.length} slices. Merged ${rest.length} into s6. No file was dropped.`)
  return kept
}

function emptyResult(status, partitions, left_out, notes, out_of_scope) {
  return {
    status,
    confirmed: [],
    plausible: [],
    refuted_count: 0,
    unverified_count: 0,
    partitions: partitions || [],
    unverified: [],
    left_out: left_out || [],
    out_of_scope: out_of_scope || [],
    collateral: [],
    notes: notes || [],
  }
}
