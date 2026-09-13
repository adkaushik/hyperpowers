const STAGES = [
  ['Route', 'picks stages and model tier'],
  ['Understand', 'read-only map, blast radius'],
  ['Plan', 'typed contract, assumptions declared'],
  ['Design', 'spec → mock → you lock it'],
  ['Build', 'test first, from the contract'],
] as const

const OUTCOMES = [
  ['0', 'all blocking passed', 'Review → Render → You', 'stage-out'],
  ['1', 'blocking failed', 'Fix loop, max 5, escalating', 'stage-gate'],
  ['78', 'could not run', 'Stops. Never a silent pass', 'stage-stop'],
] as const

/**
 * The run pipeline from the README, laid out for a page instead of a mermaid
 * renderer: one lane of stages, then the three exit codes the gate can return.
 */
export default function Pipeline() {
  return (
    <div className="panel p-5 sm:p-7">
      <ol className="m-0 grid list-none grid-cols-1 gap-2 p-0 sm:grid-cols-2 lg:grid-cols-5">
        {STAGES.map(([name, note], index) => (
          <li key={name} className="relative">
            <div className="stage h-full">
              <span className="font-mono text-[0.625rem] text-[var(--ink-dim)]">
                {String(index + 1).padStart(2, '0')}
              </span>
              <span className="stage-name">{name}</span>
              <span className="stage-note">{note}</span>
            </div>
          </li>
        ))}
      </ol>

      <div className="my-4 flex items-center gap-3">
        <span
          aria-hidden="true"
          className="h-px flex-1 bg-[var(--line-strong)]"
        />
        <span className="rule-label !text-[var(--amber)]">
          Gates · real commands, real exit codes
        </span>
        <span
          aria-hidden="true"
          className="h-px flex-1 bg-[var(--line-strong)]"
        />
      </div>

      <div className="grid gap-2 sm:grid-cols-3">
        {OUTCOMES.map(([code, meaning, result, variant]) => (
          <div key={code} className={`stage ${variant} h-full`}>
            <span className="flex items-baseline gap-2">
              <span className="font-mono text-base font-bold">{code}</span>
              <span className="stage-note !text-[var(--ink-soft)]">
                {meaning}
              </span>
            </span>
            <span className="stage-name !text-[0.6875rem] !font-medium">
              {result}
            </span>
          </div>
        ))}
      </div>

      <p className="mt-5 mb-0 text-sm leading-relaxed text-[var(--ink-soft)]">
        Design only runs on UI work, and any stage that does not apply is
        skipped: a one-file change with a rulebook precedent goes through
        Understand, Build, Gates and Review, nothing more. Each stage writes a
        typed JSON contract, and that contract is checked against its schema
        before the next stage is allowed to read it.
      </p>
    </div>
  )
}
