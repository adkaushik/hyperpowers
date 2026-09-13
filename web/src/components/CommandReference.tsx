import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { marked } from 'marked'

import {
  COMMAND_DOCS,
  COMMAND_GROUPS,
  type CommandDoc,
  type CommandGroup,
} from '#/data/commands'

/**
 * The command bodies are authored in this repo and never come from user input,
 * so parsing them once at module scope and injecting the result is fine. If
 * that ever stops being true, this needs sanitising.
 */
const RENDERED: Record<string, string> = Object.fromEntries(
  COMMAND_DOCS.map((doc) => [
    doc.slug,
    marked.parse(doc.body.trim(), { async: false, gfm: true }) as string,
  ]),
)

const BY_GROUP: Array<[CommandGroup, Array<CommandDoc>]> = COMMAND_GROUPS.map(
  (group) => [group, COMMAND_DOCS.filter((doc) => doc.group === group)],
)

const anchorOf = (slug: string) => `cmd-${slug}`

function Brief({ doc }: { doc: CommandDoc }) {
  return (
    <dl className="m-0 grid gap-0 overflow-hidden rounded-xl border border-[var(--line)] bg-[var(--bg-soft)]">
      <div className="flex min-w-0 flex-col gap-1 border-b border-[var(--line)] px-4 py-3 sm:flex-row sm:gap-4">
        <dt className="rule-label sm:w-24 sm:shrink-0 sm:pt-0.5">Invoke</dt>
        <dd className="m-0 min-w-0 overflow-x-auto font-mono text-[0.8125rem] whitespace-pre text-[var(--amber)]">
          {doc.invoke}
        </dd>
      </div>
      <div className="flex min-w-0 flex-col gap-1 border-b border-[var(--line)] px-4 py-3 sm:flex-row sm:gap-4">
        <dt className="rule-label sm:w-24 sm:shrink-0 sm:pt-0.5">When</dt>
        <dd className="m-0 text-sm leading-relaxed text-[var(--ink-soft)]">
          {doc.when}
        </dd>
      </div>
      <div className="flex min-w-0 flex-col gap-1 px-4 py-3 sm:flex-row sm:gap-4">
        <dt className="rule-label sm:w-24 sm:shrink-0 sm:pt-0.5">Expect</dt>
        <dd className="m-0 text-sm leading-relaxed text-[var(--ink-soft)]">
          {doc.expect}
        </dd>
      </div>
    </dl>
  )
}

export function CommandReference() {
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(COMMAND_DOCS[0].slug)
  const sectionRef = useRef<HTMLDivElement | null>(null)

  const slugs = useMemo(() => COMMAND_DOCS.map((doc) => doc.slug), [])

  // A link to one command should land on that command, not on a collapsed
  // panel the visitor then has to open by hand.
  useEffect(() => {
    const openFromHash = () => {
      const hash = window.location.hash.replace('#', '')
      if (!hash.startsWith('cmd-')) return
      const slug = hash.slice(4)
      if (!slugs.includes(slug)) return
      setOpen(true)
      setActive(slug)
      // Wait for the panel to render at full height before scrolling to it.
      requestAnimationFrame(() => {
        document.getElementById(hash)?.scrollIntoView({ block: 'start' })
      })
    }
    openFromHash()
    window.addEventListener('hashchange', openFromHash)
    return () => window.removeEventListener('hashchange', openFromHash)
  }, [slugs])

  // Highlight whichever command is currently under the top of the viewport.
  useEffect(() => {
    if (!open) return
    const targets = slugs
      .map((slug) => document.getElementById(anchorOf(slug)))
      .filter((el): el is HTMLElement => el !== null)
    if (targets.length === 0) return

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0]
        if (visible) setActive(visible.target.id.slice(4))
      },
      { rootMargin: '-88px 0px -70% 0px', threshold: 0 },
    )
    targets.forEach((el) => observer.observe(el))
    return () => observer.disconnect()
  }, [open, slugs])

  const collapse = useCallback(() => {
    setOpen(false)
    sectionRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' })
  }, [])

  return (
    <div ref={sectionRef} className="scroll-mt-20">
      <div className="relative">
        <div
          id="command-reference"
          className={
            open
              ? 'grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)] lg:gap-10'
              : 'grid gap-6'
          }
        >
          {/* Index. While the reference is collapsed it would stand taller
              than the clipped preview beside it, so it waits for the open. */}
          <nav
            aria-label="Commands"
            hidden={!open}
            className="lg:sticky lg:top-20 lg:max-h-[calc(100dvh-6rem)] lg:self-start lg:overflow-y-auto lg:pr-2"
          >
            <div className="grid gap-5">
              {BY_GROUP.map(([group, docs]) => (
                <div key={group}>
                  <p className="rule-label mb-2">{group}</p>
                  <ul className="m-0 grid list-none gap-0.5 p-0">
                    {docs.map((doc) => {
                      const isActive = open && active === doc.slug
                      return (
                        <li key={doc.slug}>
                          <a
                            href={`#${anchorOf(doc.slug)}`}
                            onClick={() => {
                              setOpen(true)
                              setActive(doc.slug)
                            }}
                            className={`block rounded-md px-2 py-1.5 font-mono text-[0.78rem] leading-snug no-underline transition-colors ${
                              isActive
                                ? 'bg-[var(--amber-bg)] text-[var(--amber)]'
                                : 'text-[var(--ink-soft)] hover:bg-[var(--panel-raised)] hover:text-[var(--ink)]'
                            }`}
                          >
                            {/* Bare name only: arguments make the index wrap. */}
                            {doc.name.replace('/hyperpower:', '').split(' ')[0]}
                          </a>
                        </li>
                      )
                    })}
                  </ul>
                </div>
              ))}
            </div>
          </nav>

          {/* Details */}
          <div
            aria-hidden={!open}
            className={`relative grid min-w-0 gap-4 ${
              open ? '' : 'max-h-[22rem] overflow-hidden'
            }`}
          >
            {COMMAND_DOCS.map((doc) => (
              <article
                key={doc.slug}
                id={anchorOf(doc.slug)}
                className="panel min-w-0 scroll-mt-20 p-5 sm:p-7"
              >
                <header className="mb-4">
                  <p className="rule-label mb-2">{doc.group}</p>
                  <h3 className="m-0 mb-1 font-mono text-base font-bold break-words text-[var(--ink)] sm:text-lg">
                    {doc.name}
                  </h3>
                  <p className="m-0 text-sm text-[var(--ink-dim)]">{doc.note}</p>
                </header>

                <Brief doc={doc} />

                <div
                  className="md-body mt-5"
                  // Authored in this repo, parsed at build time. See RENDERED.
                  dangerouslySetInnerHTML={{ __html: RENDERED[doc.slug] }}
                />
              </article>
            ))}

            {!open ? (
              <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-b from-transparent to-[var(--bg)]" />
            ) : null}
          </div>
        </div>
      </div>

      <div
        className={`flex justify-center ${open ? 'mt-6' : '-mt-8 relative z-1'}`}
      >
        <button
          type="button"
          className="btn btn-ghost"
          aria-expanded={open}
          aria-controls="command-reference"
          onClick={() => (open ? collapse() : setOpen(true))}
        >
          {open ? 'Collapse the reference' : 'Read the full reference'}
          <span aria-hidden="true" className={open ? 'rotate-180' : undefined}>
            ↓
          </span>
        </button>
      </div>
    </div>
  )
}
