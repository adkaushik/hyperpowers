import { Suspense } from 'react'
import { Await, Link, createFileRoute } from '@tanstack/react-router'
import { CommandReference } from '../components/CommandReference'
import CopyCommand from '../components/CopyCommand'
import Pipeline from '../components/Pipeline'
import { ArrowRightIcon, GitHubIcon } from '../components/icons'
import { getRepoStats, type RepoStats } from '../server/repo.functions'

const REPO_URL = 'https://github.com/adkaushik/hyperpowers'

export const Route = createFileRoute('/')({
  // Marketing copy is the whole point of this route: render it on the server so
  // it is in the first byte for crawlers and slow connections.
  ssr: true,
  loader: () => {
    // Not awaited: the repo stats stream in after the shell, so a slow GitHub
    // response cannot hold up the document.
    return { statsPromise: getRepoStats() }
  },
  component: Landing,
})

function StatsStrip() {
  const { statsPromise } = Route.useLoaderData()

  return (
    <Suspense
      fallback={
        <div className="flex gap-2">
          {[0, 1, 2].map((key) => (
            <span key={key} className="shimmer h-6 w-24" />
          ))}
        </div>
      }
    >
      <Await promise={statsPromise}>{(stats) => <Stats stats={stats} />}</Await>
    </Suspense>
  )
}

function Stats({ stats }: { stats: RepoStats }) {
  const items = [
    stats.stars === null ? null : [`${stats.stars}`, 'stars'],
    stats.forks === null ? null : [`${stats.forks}`, 'forks'],
    [stats.license ?? 'MIT', 'licence'],
    stats.pushedAt === null
      ? null
      : [
          new Date(stats.pushedAt).toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          }),
          'last push',
        ],
  ].filter((item): item is [string, string] => item !== null)

  return (
    <div className="flex flex-wrap items-center gap-2">
      {items.map(([value, label]) => (
        <span
          key={label}
          className="inline-flex items-baseline gap-1.5 rounded-lg border border-[var(--line)] bg-[var(--panel)] px-2.5 py-1"
        >
          <span className="font-mono text-xs font-bold text-[var(--ink)]">
            {value}
          </span>
          <span className="text-[0.6875rem] text-[var(--ink-dim)]">
            {label}
          </span>
        </span>
      ))}
    </div>
  )
}

function SectionHeading({
  kicker,
  title,
  children,
}: {
  kicker: string
  title: string
  children?: React.ReactNode
}) {
  return (
    <div className="mb-6 max-w-2xl">
      <p className="kicker mb-2">{kicker}</p>
      <h2 className="mb-3 text-2xl font-semibold tracking-tight text-[var(--ink)] sm:text-3xl">
        {title}
      </h2>
      {children ? (
        <p className="m-0 text-sm leading-relaxed text-[var(--ink-soft)] sm:text-base">
          {children}
        </p>
      ) : null}
    </div>
  )
}

const AGENTS = [
  ['Archivist', 'decision records and the mistakes log'],
  ['Promoter', 'rules, when a mistake crosses threshold'],
  ['Gardener', 'compacts the archive, on command'],
  ['Scout', 'opportunities you noticed but did not do'],
  ['Janitor', 'dependency and migration debt'],
] as const

function Landing() {
  return (
    <main className="px-4 pt-14 sm:pt-20">
      {/* Hero */}
      <section className="page-wrap rise-in">
        <p className="kicker mb-4">Claude Code plugin</p>
        <h1 className="mb-5 max-w-3xl text-4xl leading-[1.05] font-semibold tracking-tight text-[var(--ink)] sm:text-6xl">
          A gated pipeline for Claude Code.
        </h1>
        <p className="mb-7 max-w-2xl text-base leading-relaxed text-[var(--ink-soft)] sm:text-lg">
          You hand it one requirement. It routes the work through stages, runs
          your own type, test and build commands at the gate, and writes down
          what it decided on the way through. It works on any stack: one setup
          command reads the repo and configures the rest.
        </p>

        <div className="mb-7 flex flex-wrap items-center gap-3">
          <Link to="/signin" className="btn btn-primary">
            Sign in to get access
            <ArrowRightIcon />
          </Link>
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            className="btn btn-ghost"
          >
            <GitHubIcon size={16} />
            View the source
          </a>
        </div>

        <StatsStrip />

        <div className="mt-8 grid gap-2 lg:max-w-3xl">
          <CopyCommand command="npx hyperpowers-claude" prompt="$" />
          <CopyCommand command="/hyperpower:init" prompt="›" />
        </div>
        <p className="mt-3 text-xs text-[var(--ink-dim)]">
          The installer prints an activation code. Enter it here while signed in
          and it installs the plugin. Restart the session, then run{' '}
          <code>/hyperpower:init</code> once per repository: it detects your
          stack, asks at most six questions, and writes{' '}
          <code>hyperpower.yml</code>. Budget five minutes the first time.
        </p>
      </section>

      {/* Pipeline */}
      <section id="pipeline" className="page-wrap mt-20 scroll-mt-20">
        <SectionHeading kicker="The pipeline" title="How a run goes">
          <code>/hyperpower:run "add a settings screen"</code> starts it. If you
          want to see the stage list before paying for it, run{' '}
          <code>/hyperpower:route</code> with the same requirement and it stops
          after printing.
        </SectionHeading>
        <Pipeline />
      </section>

      {/* Gates / journal / assumptions */}
      <section className="page-wrap mt-20 grid gap-4 lg:grid-cols-3">
        <article className="panel min-w-0 p-6">
          <p className="rule-label mb-3">Gates</p>
          <h3 className="mb-3 text-lg font-semibold text-[var(--ink)]">
            What a gate actually does
          </h3>
          <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
            It runs a command from your config (<code>tsc --noEmit</code>, your
            test command, your build) and reads the exit code. Nothing here is a
            model deciding whether the work looks finished.
          </p>
          <p className="m-0 text-sm leading-relaxed text-[var(--ink-soft)]">
            A gate that cannot run reports that it did not run. A missing tool
            or a timeout never counts as a pass. Nine gates are in the schema,
            and you choose which ones block and which only warn.
          </p>
        </article>

        <article className="panel min-w-0 p-6">
          <p className="rule-label mb-3">The journal</p>
          <h3 className="mb-3 text-lg font-semibold text-[var(--ink)]">
            Every run leaves a folder behind
          </h3>
          <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
            It is written as the run goes, not summarised afterwards:{' '}
            <code>meta.json</code>, one contract per step, the full output of
            every gate command, a line per model call and a line per failure.
            You can close the session and still go back through it.
          </p>
          <pre className="m-0 overflow-x-auto rounded-lg border border-[var(--line)] bg-[var(--bg-soft)] p-3 font-mono text-[0.6875rem] leading-relaxed text-[var(--ink-soft)]">
{`Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed`}
          </pre>
        </article>

        <article className="panel min-w-0 p-6">
          <p className="rule-label mb-3">Assumptions</p>
          <h3 className="mb-3 text-lg font-semibold text-[var(--ink)]">
            Written down, then checked
          </h3>
          <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
            Each step records what it took for granted and keeps going, so you
            are never sitting there answering questions. By gate time the code
            exists, so a cheap model re-reads the target and marks each
            assumption verified, refuted or unresolved.
          </p>
          <pre className="m-0 overflow-x-auto rounded-lg border border-[var(--line)] bg-[var(--bg-soft)] p-3 font-mono text-[0.6875rem] leading-relaxed text-[var(--ink-soft)]">
{`{"id":"a1",
 "claim":"settings API returns a bare array",
 "source":"inferred",
 "confidence":"low",
 "status":"declared"}`}
          </pre>
        </article>
      </section>

      {/* Memory */}
      <section id="memory" className="page-wrap mt-20 scroll-mt-20">
        <SectionHeading kicker="Memory" title="Memory is split in two">
          The archive holds full decision records: options rejected and why,
          what was tried and failed, the constraint that forced the choice.
          Keeping it costs nothing, because it never gets loaded into context.
        </SectionHeading>

        <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
          <div className="panel overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-[var(--line)]">
                  <th className="rule-label p-4 text-left font-normal" />
                  <th className="p-4 text-left font-mono text-xs font-bold text-[var(--blue)]">
                    Rulebook
                  </th>
                  <th className="p-4 text-left font-mono text-xs font-bold text-[var(--ink-soft)]">
                    Decision archive
                  </th>
                </tr>
              </thead>
              <tbody>
                {[
                  [
                    'Contains',
                    'how to behave in this repo',
                    'why things are the way they are',
                  ],
                  ['Size', 'capped at 30 rules', 'unbounded'],
                  ['Loaded', 'every run', 'never'],
                  ['Read', 'always', 'only when you ask'],
                ].map(([label, rulebook, archive]) => (
                  <tr
                    key={label}
                    className="border-b border-[var(--line)] last:border-0"
                  >
                    <td className="rule-label p-4">{label}</td>
                    <td className="p-4 text-[var(--ink)]">{rulebook}</td>
                    <td className="p-4 text-[var(--ink-soft)]">{archive}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="panel p-6">
            <p className="rule-label mb-3">Promotion</p>
            <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
              When the same mistake happens three times, a background agent
              promotes it into the rulebook. Once you are at the cap, a new rule
              has to beat the weakest rule already there, which gets demoted to
              make room.
            </p>
            <p className="m-0 text-sm leading-relaxed text-[var(--ink)]">
              The cap is the point: without it, every run would get slower as
              the rulebook grew.
            </p>
          </div>
        </div>

        <div className="mt-4 grid gap-4 lg:grid-cols-[1fr_1.3fr]">
          <div className="panel p-6">
            <p className="rule-label mb-3">Slop control</p>
            <h3 className="mb-3 text-lg font-semibold text-[var(--ink)]">
              Cheap checks before expensive ones
            </h3>
            <p className="m-0 text-sm leading-relaxed text-[var(--ink-soft)]">
              <code>antislop</code> and <code>ai-slop-detector</code> run in the
              gate: offline, about a second, no tokens. A model sweep picks up
              what they cannot see, like over-abstraction, swallowed exceptions
              and invented helpers that duplicate something already in the repo.
            </p>
          </div>

          <div className="panel p-6">
            <p className="rule-label mb-3">
              Five agents, running once the work is done
            </p>
            <ul className="m-0 list-none space-y-2 p-0">
              {AGENTS.map(([name, writes]) => (
                <li
                  key={name}
                  className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-[var(--line)] pb-2 last:border-0 last:pb-0"
                >
                  <span className="font-mono text-xs font-bold text-[var(--green)]">
                    {name}
                  </span>
                  <span className="text-sm text-[var(--ink-soft)]">
                    {writes}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      {/* Commands */}
      <section id="commands" className="page-wrap mt-20 scroll-mt-20">
        <SectionHeading
          kicker="Commands"
          title="The ones you will actually type"
        >
          Twenty-six in total, in six groups. Each one below has how to call it,
          when to reach for it, and what you get back.{' '}
          <code>/hyperpower:help</code> prints the same list in your terminal.
        </SectionHeading>

        <CommandReference />
      </section>

      {/* Install + privacy */}
      <section
        id="install"
        className="page-wrap mt-20 grid scroll-mt-20 gap-4 lg:grid-cols-2"
      >
        <div className="panel p-6">
          <p className="kicker mb-2">Install</p>
          <h3 className="mb-4 text-xl font-semibold text-[var(--ink)]">
            Getting set up
          </h3>
          <div className="grid gap-2">
            <CopyCommand command="npx hyperpowers-claude" prompt="$" />
            <CopyCommand command="/hyperpower:init" prompt="›" />
          </div>
          <ol className="mt-4 mb-0 grid gap-2 pl-5 text-sm leading-relaxed text-[var(--ink-soft)]">
            <li>The installer prints a one-time activation code and waits.</li>
            <li>
              Sign in here and enter the code. The installer then unpacks the
              plugin, registers it as a local marketplace and installs it.
            </li>
            <li>
              Restart the session and run <code>/hyperpower:init</code> in
              whichever repository you want it to learn.
            </li>
          </ol>
          <p className="mt-4 mb-0 text-sm leading-relaxed text-[var(--ink-soft)]">
            Config lives in <code>hyperpower.yml</code> at the repo root and is
            meant to be committed. If you need to override something on one
            machine, <code>hyperpower.local.yml</code> does that and stays
            gitignored. <code>npx hyperpowers-claude uninstall</code> removes
            everything it put on disk.
          </p>
        </div>

        <div className="panel p-6">
          <p className="kicker mb-2">Privacy</p>
          <h3 className="mb-4 text-xl font-semibold text-[var(--ink)]">
            Everything stays local
          </h3>
          <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
            There is no remote destination anywhere in the codebase, and no
            opt-in that would add one. Usage and cost data are just files inside
            your repository.
          </p>
          <p className="mb-4 text-sm leading-relaxed text-[var(--ink-soft)]">
            Turning on <code>telemetry.redact_paths</code> hashes file paths
            before they reach an aggregate view. Treat that as redaction rather
            than anonymity: the hash is salted from{' '}
            <code>.hyperpower/redact-salt</code>, so anyone who has both the
            repo and that file can match a path back.
          </p>
          <CopyCommand command="/hyperpower:telemetry purge" prompt="›" />
        </div>
      </section>

      {/* CTA */}
      <section className="page-wrap mt-20">
        <div className="panel-raised flex flex-col items-start gap-5 p-8 sm:flex-row sm:items-center sm:justify-between sm:p-10">
          <div className="max-w-xl">
            <h2 className="mb-2 text-2xl font-semibold tracking-tight text-[var(--ink)]">
              Getting access
            </h2>
            <p className="m-0 text-sm leading-relaxed text-[var(--ink-soft)]">
              Sign in with your email and we send a six-digit code, so there is
              no password to remember. Your account is where you claim the
              activation code that <code>npx hyperpowers-claude</code> prints.
            </p>
          </div>
          <Link to="/signin" className="btn btn-primary flex-shrink-0">
            Sign in
            <ArrowRightIcon />
          </Link>
        </div>
      </section>
    </main>
  )
}
