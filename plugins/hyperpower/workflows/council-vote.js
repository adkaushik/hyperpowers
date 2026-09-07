export const meta = {
  name: 'hyperpower-council-vote',
  description: 'Put one expensive-to-reverse decision to independent persona votes, then synthesize a recommendation.',
  whenToUse:
    'For a decision that costs more to reverse than to make: a schema shape, a public interface, a dependency you will live with, a migration order. Skip it for anything a later commit can undo cheaply — one agent is enough there, and the council costs four judgment-tier calls plus a synthesis.',
  phases: [
    { title: 'Ground', detail: 'One read-only agent pulls the code excerpts the decision turns on' },
    { title: 'Voices', detail: 'Reviewer, skeptic, builder, and generalist vote independently and in parallel' },
    { title: 'Synthesize', detail: 'One agent turns the ballot into a recommendation with the dissent attached' },
  ],
}

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

const a = args && typeof args === 'object' ? args : {}
const question = typeof a.question === 'string' ? a.question.trim() : ''
const context = typeof a.context === 'string' ? a.context.trim() : ''
const note = typeof a.note === 'string' ? a.note.trim() : ''
const paths = Array.isArray(a.paths) ? a.paths.filter((p) => typeof p === 'string' && p.trim()).map((p) => p.trim()) : []
const groundMode = ['auto', 'always', 'never'].includes(a.ground) ? a.ground : 'auto'
const options = buildOptions(a.options)

function buildOptions(raw) {
  if (!Array.isArray(raw)) return []
  const out = []
  raw.forEach((entry, i) => {
    const label = typeof entry === 'string' ? entry.trim() : entry && typeof entry.label === 'string' ? entry.label.trim() : ''
    if (!label) return
    out.push({
      option_id: `o${out.length + 1}`,
      label,
      detail: entry && typeof entry.detail === 'string' ? entry.detail.trim() : '',
    })
  })
  return out
}

if (!question) {
  log('council-vote: args.question is missing. The council does not guess the decision.')
  return refuseToRun('args.question is required. Pass the decision as one question.')
}

if (options.length < 2) {
  log('council-vote: fewer than two options. The council does not invent the choices.')
  return refuseToRun('args.options must hold at least two options. Pass them as strings, or as {label, detail} objects.')
}

if (options.length > 5) {
  log(`council-vote: ${options.length} options supplied. Voting on more than five splits the tally into noise.`)
}

// ---------------------------------------------------------------------------
// Roster
//
// Persona-only, and deliberately so. There is no external vendor CLI routing
// here and none is planned. Routing a vote to another vendor's CLI would bill
// an account the user did not point at this repo.
//
// One spelling per voice: the plugin namespace plus the bare `name` in
// agents/<role>.md. If it does not resolve, fall back to an inline role brief.
// The fallback is logged. A silent fallback would report a persona vote that
// never ran. A bare `reviewer` is never tried: it would resolve to a same-named
// agent in the user's own ~/.claude/agents/ and vote from other instructions.
// ---------------------------------------------------------------------------

const ROSTER = [
  {
    voice: 'reviewer',
    agentTypes: ['hyperpower:reviewer'],
    brief: 'Act as the hyperpower reviewer. You are read-only. You find defects and anchor every claim to a file:line.',
    lens: [
      'Your lens is defects and blast radius.',
      'For each option, name what breaks: the callers it changes, the seams where two sides would disagree on shape or nullability, the edge cases it makes reachable.',
      'Weigh an option down when it widens the blast radius. Weigh it up when it narrows one.',
    ].join('\n'),
  },
  {
    voice: 'skeptic',
    agentTypes: ['hyperpower:skeptic'],
    brief: 'Act as the hyperpower skeptic. You are read-only. You try to refute claims by reading code, and you never refute for lack of a reproduction.',
    lens: [
      'Your lens is refutation.',
      'For each option, state the claim it depends on, then try to refute that claim against the repo.',
      'Vote for the option whose load-bearing claim survived your hardest attempt to break it.',
      'Do not vote for an option because it is cautious. Caution is not evidence.',
    ].join('\n'),
  },
  {
    voice: 'builder',
    agentTypes: ['hyperpower:builder'],
    brief: 'Act as the hyperpower builder. You implement from a typed contract, test first, and declare what you assumed.',
    lens: [
      'Your lens is implementation cost and testability.',
      'For each option, name the files that change, the test you would write first, and the migration the repo would have to run.',
      'Do not write code and do not edit any file in this vote. You are estimating, not building.',
      'Weigh an option down when you cannot name a test that would catch it going wrong.',
    ].join('\n'),
  },
  {
    voice: 'generalist',
    // The main agent cannot vote from inside the script, so a generalist
    // subagent with full repo access holds that seat. It is labelled as such in
    // the tally rather than passed off as the main agent's own vote.
    agentTypes: [],
    brief: 'You hold the main agent judgment seat on this council. You have no persona. Read the repo and judge overall fit.',
    lens: [
      'Your lens is overall fit.',
      'Weigh how each option sits against how this repo already works, what CODEBASE_RULEBOOK.md says, and what the decision archive under the configured decisions directory already settled.',
      'You are the only voice that is not specialised. Say plainly when the specialists are optimising for something this repo does not need.',
    ].join('\n'),
  },
]

async function spawn(member, prompt, opts) {
  for (const type of member.agentTypes) {
    try {
      return await agent(prompt, Object.assign({}, opts, { agentType: type }))
    } catch (err) {
      continue
    }
  }
  if (member.agentTypes.length) {
    log(`${member.voice}: no registered agent type resolved. Running the inline role brief instead.`)
  }
  return await agent(`${member.brief}\n\n${prompt}`, opts)
}

// ---------------------------------------------------------------------------
// Schemas
//
// Every voice returns through a schema. A voice that abstains says so in the
// vote field with a reason attached, so it lands in the report instead of
// vanishing from the tally. A voice that dies returns null from parallel() and
// is reported as dropped for the same reason.
// ---------------------------------------------------------------------------

const GROUND_SCHEMA = {
  type: 'object',
  properties: {
    excerpts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          lines: { type: 'string' },
          quote: { type: 'string' },
          relevance: { type: 'string' },
        },
        required: ['path', 'lines', 'quote', 'relevance'],
      },
    },
    constraints: { type: 'array', items: { type: 'string' } },
    unknowns: { type: 'array', items: { type: 'string' } },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['excerpts', 'constraints', 'unknowns', 'notes'],
}

const VOTE_SCHEMA = {
  type: 'object',
  properties: {
    voice: { type: 'string' },
    vote: { type: 'string', enum: options.map((o) => o.option_id).concat(['ABSTAIN']) },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasons: { type: 'array', items: { type: 'string' } },
    risks: { type: 'array', items: { type: 'string' } },
    second_choice: { type: 'string', enum: options.map((o) => o.option_id).concat(['NONE']) },
    reversal_cost: { type: 'string' },
    abstain_reason: { type: 'string' },
  },
  required: ['voice', 'vote', 'confidence', 'reasons', 'risks', 'second_choice', 'reversal_cost', 'abstain_reason'],
}

const SYNTH_SCHEMA = {
  type: 'object',
  properties: {
    option_id: { type: 'string', enum: options.map((o) => o.option_id).concat(['NONE']) },
    recommendation: { type: 'string' },
    follows_tally: { type: 'boolean' },
    rationale: { type: 'array', items: { type: 'string' } },
    dissent: { type: 'array', items: { type: 'string' } },
    open_risks: { type: 'array', items: { type: 'string' } },
    reversal_condition: { type: 'string' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
  required: [
    'option_id',
    'recommendation',
    'follows_tally',
    'rationale',
    'dissent',
    'open_risks',
    'reversal_condition',
    'confidence',
  ],
}

// ---------------------------------------------------------------------------
// Shared prompt fragments
// ---------------------------------------------------------------------------

const CONFIG_BLOCK = [
  'Config. Read hyperpower.yml at the repo root, then hyperpower.local.yml over it, field by field.',
  'Fields used: paths.source for where the implementation lives, paths.ignore to skip generated and vendored trees, memory.decisions_dir for the decision archive.',
  'If neither config file exists, search the whole tree except .git, skip node_modules and dist, and look for the archive in decisions/. Do not ask anyone to create a config.',
].join('\n')

const OPTIONS_BLOCK = options
  .map((o) => `  ${o.option_id}: ${o.label}${o.detail ? `\n      detail: ${o.detail}` : ''}`)
  .join('\n')

const DECISION_BLOCK = [
  `Decision: ${question}`,
  '',
  'Options:',
  OPTIONS_BLOCK,
  context ? `\nContext supplied by the caller:\n${context}` : '',
  note ? `\nCaller note, for context only: ${note}` : '',
]
  .filter(Boolean)
  .join('\n')

const NO_RENDER_RULES =
  'Do not apply the cap-at-five rule and do not apply ADHD shaping. This is an agent-to-agent handoff, not a rendered view.'

// ---------------------------------------------------------------------------
// Phase 1 — Ground (optional)
// ---------------------------------------------------------------------------

const wantGround = groundMode === 'always' || (groundMode === 'auto' && paths.length > 0)
let ground = null

if (wantGround) {
  phase('Ground')
  log(paths.length ? `Ground: reading ${paths.length} path(s).` : 'Ground: no paths given, locating the relevant code first.')

  ground = await agent(
    [
      'Gather the code this decision turns on. You are read-only.',
      'Do not edit, create, or delete any file. Use Bash only for read commands: git log, git show, rg, ls, cat.',
      '',
      DECISION_BLOCK,
      '',
      CONFIG_BLOCK,
      '',
      paths.length
        ? `Start from these paths:\n${paths.map((p) => `  - ${p}`).join('\n')}`
        : 'No paths were given. Find the code the decision turns on by grepping for the nouns in the question.',
      '',
      'Steps.',
      '1. Read the starting paths in full, then follow imports and callers one hop out.',
      '2. Pull the excerpts that constrain the choice. Each excerpt needs a path, a line range, a short verbatim quote, and one line saying which option it constrains.',
      '3. List constraints: facts in the code that rule an option in or out.',
      '4. List unknowns: what the repo does not settle, and where you looked.',
      '',
      'At most 12 excerpts. Rank them by how much they constrain the choice, and say in notes how many you left out.',
      'Do not recommend an option. Do not evaluate the options. You supply evidence, not a vote.',
      NO_RENDER_RULES,
    ].join('\n'),
    { label: 'ground the decision', phase: 'Ground', schema: GROUND_SCHEMA }
  )

  if (!ground) {
    log('Ground returned nothing. The voices will read the repo themselves.')
  } else {
    // Normalise before reading a length. A ground result missing one array
    // would throw here and kill the council before any voice ran.
    ground = {
      excerpts: Array.isArray(ground.excerpts) ? ground.excerpts : [],
      constraints: Array.isArray(ground.constraints) ? ground.constraints : [],
      unknowns: Array.isArray(ground.unknowns) ? ground.unknowns : [],
      notes: Array.isArray(ground.notes) ? ground.notes : [],
    }
    log(`Ground: ${ground.excerpts.length} excerpt(s), ${ground.constraints.length} constraint(s), ${ground.unknowns.length} unknown(s).`)
  }
} else {
  log(groundMode === 'never' ? 'Ground: skipped by args.ground=never.' : 'Ground: skipped, no paths given and the decision is not code-tied.')
}

const groundBlock = ground
  ? [
      '',
      'Grounding evidence, gathered by a read-only agent before the vote:',
      JSON.stringify({ excerpts: ground.excerpts, constraints: ground.constraints, unknowns: ground.unknowns }, null, 2),
      'This evidence is a starting point, not a limit. Read further when you need to.',
    ].join('\n')
  : ''

// ---------------------------------------------------------------------------
// Phase 2 — Voices
//
// parallel(), and that is the point. The voices must not see each other. Any
// shape that let one vote inform another would produce agreement instead of
// independence, and the tally would mean nothing.
// ---------------------------------------------------------------------------

phase('Voices')
log(`Voices: ${ROSTER.length} independent votes on ${options.length} option(s).`)

const ballotsRaw = await parallel(
  ROSTER.map((member) => () =>
    spawn(member, votePrompt(member), {
      label: `${member.voice} votes`,
      phase: 'Voices',
      schema: VOTE_SCHEMA,
      effort: 'high',
    })
  )
)

const counted = []
const abstains = []
const dropped = []

ROSTER.forEach((member, i) => {
  const b = ballotsRaw[i]
  if (!b) {
    dropped.push({ voice: member.voice, reason: 'The agent returned no result. This voice never voted.' })
    return
  }
  const record = {
    voice: member.voice,
    vote: b.vote,
    confidence: b.confidence,
    reasons: b.reasons || [],
    risks: b.risks || [],
    second_choice: b.second_choice || 'NONE',
    reversal_cost: b.reversal_cost || '',
  }
  if (b.vote === 'ABSTAIN') {
    abstains.push(
      Object.assign({}, record, {
        reason: (b.abstain_reason || '').trim() || 'The voice abstained and gave no reason.',
      })
    )
    return
  }
  counted.push(record)
})

if (dropped.length) log(`Voices dropped: ${dropped.map((d) => d.voice).join(', ')}. They are reported, not counted.`)
if (abstains.length) log(`Voices abstained: ${abstains.map((x) => x.voice).join(', ')}. Abstains are never counted as votes.`)

// Abstains and dropped voices are excluded from the denominator. Counting an
// abstain as a vote for anything would invent a position the voice refused to take.
const tally = {
  roster_size: ROSTER.length,
  counted: counted.length,
  abstained: abstains.length,
  dropped: dropped.length,
  options: options.map((o) => ({
    option_id: o.option_id,
    label: o.label,
    votes: counted.filter((c) => c.vote === o.option_id).length,
    voters: counted.filter((c) => c.vote === o.option_id).map((c) => c.voice),
    second_choice_votes: counted.filter((c) => c.second_choice === o.option_id).length,
  })),
  leader: null,
  tied_options: [],
  margin: 0,
  tie: false,
}

const ranked = tally.options.slice().sort((x, y) => y.votes - x.votes)
if (counted.length && ranked[0].votes > 0) {
  const top = ranked[0].votes
  tally.margin = top - (ranked[1] ? ranked[1].votes : 0)
  tally.tied_options = tally.options.filter((o) => o.votes === top).map((o) => o.option_id)
  tally.tie = tally.tied_options.length > 1
  // A tie has no leader. Naming one would hand the synthesizer a majority that
  // does not exist.
  tally.leader = tally.tie ? null : ranked[0].option_id
}

log(`Tally: ${tally.options.map((o) => `${o.option_id}=${o.votes}`).join(' ')} (${counted.length}/${ROSTER.length} counted).`)

if (!counted.length) {
  log('No voice cast a countable vote. There is nothing to synthesize.')
  return {
    status: 'no_quorum',
    question,
    options,
    tally,
    abstains,
    dropped,
    voices: counted,
    grounded: Boolean(ground),
    ground: ground || null,
    synthesis: null,
  }
}

// ---------------------------------------------------------------------------
// Phase 3 — Synthesize
// ---------------------------------------------------------------------------

phase('Synthesize')

const synthesis = await agent(
  [
    'Turn a council ballot into one recommendation. You are read-only.',
    'Do not edit, create, or delete any file.',
    '',
    DECISION_BLOCK,
    groundBlock,
    '',
    'The ballot:',
    JSON.stringify({ tally, votes: counted, abstains, dropped }, null, 2),
    '',
    'Rules.',
    '1. The tally is evidence, not a verdict. Read the reasons, not the count.',
    `2. ${abstains.length} voice(s) abstained and ${dropped.length} returned nothing. Neither counts as a vote. Say in dissent what their absence leaves unchecked.`,
    '3. Set follows_tally to false whenever your option_id is not the tally leader, and put the reason first in rationale.',
    tally.tie
      ? `4. The tally is tied across ${tally.tied_options.join(' and ')}. There is no leader. follows_tally is true when your option_id is one of those, and the tie is what you are here to break.`
      : '4. The tally has a leader. Departing from it is allowed and sometimes right. Say why, first, in rationale.',
    '5. Put every minority position in dissent, with the voice that held it and the risk it named. Never drop a dissent because the majority disagreed.',
    '6. reversal_condition is one sentence naming the observation that should make someone revisit this. It goes straight into the decision record.',
    '',
    'Return option_id NONE only when the evidence rules out every option. NONE requires the rationale to name what a valid option would need.',
    'Verify a claim in the repo before you rely on it. A voice can be wrong about the code.',
    NO_RENDER_RULES,
  ].join('\n'),
  { label: 'synthesize the ballot', phase: 'Synthesize', schema: SYNTH_SCHEMA, effort: 'high' }
)

if (!synthesis) {
  log('Synthesis returned nothing. The tally and the ballots stand on their own.')
} else {
  const chosen = options.find((o) => o.option_id === synthesis.option_id)
  log(`Recommendation: ${chosen ? chosen.label : 'none of the options'} (${synthesis.follows_tally ? 'follows' : 'departs from'} the tally).`)
}

return {
  status: 'decided',
  question,
  options,
  tally,
  abstains,
  dropped,
  voices: counted,
  grounded: Boolean(ground),
  ground: ground || null,
  synthesis: synthesis || null,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function votePrompt(member) {
  return [
    'Vote on one decision. You vote alone. You will not see the other voices, and they will not see you.',
    '',
    DECISION_BLOCK,
    groundBlock,
    '',
    CONFIG_BLOCK,
    '',
    member.lens,
    '',
    'Steps.',
    '1. Read the repo for what your lens needs. Verify anything the caller asserted rather than taking it.',
    '2. Judge every option against your lens, including the ones you will not vote for.',
    `3. Vote by option_id. Set voice to ${JSON.stringify(member.voice)}.`,
    '4. Give reasons anchored to a file:line, a command, or a named constraint. An unanchored reason is an opinion.',
    '5. Name the risks your chosen option carries. A vote with no risks listed is not a vote, it is a preference.',
    '',
    'reversal_cost is one sentence: what it would take to undo this option after it ships.',
    'second_choice is the option you would take if yours were ruled out, or NONE when no other option is acceptable.',
    '',
    'Abstain rule. Vote ABSTAIN only when the evidence available cannot separate the options for your lens. Fill abstain_reason with what is missing and where you looked for it.',
    'The exception is the whole point: do not abstain because the options are close. When they are close, pick one and set confidence to low.',
    'Do not abstain to avoid committing. An abstain is reported to the user as a voice that could not judge.',
    'When you vote, leave abstain_reason as an empty string.',
    '',
    'Do not edit, create, or delete any file. Do not run the test suite, install anything, or start a server.',
    NO_RENDER_RULES,
  ].join('\n')
}

function refuseToRun(reason) {
  return {
    status: 'not_run',
    reason,
    question,
    options,
    tally: null,
    abstains: [],
    dropped: [],
    voices: [],
    grounded: false,
    ground: null,
    synthesis: null,
  }
}
