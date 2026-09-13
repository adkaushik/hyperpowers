import { Link } from '@tanstack/react-router'
import { GitHubIcon } from './icons'

const REPO_URL = 'https://github.com/adkaushik/hyperpowers'

export default function Footer({ signedIn }: { signedIn: boolean }) {
  const year = new Date().getFullYear()

  return (
    <footer className="mt-24 hairline px-4 py-10 text-[var(--ink-soft)]">
      <div className="page-wrap grid gap-8 sm:grid-cols-[1.4fr_1fr_1fr]">
        <div>
          <p className="mb-2 font-mono text-sm font-bold text-[var(--ink)]">
            hyperpowers
          </p>
          <p className="m-0 max-w-sm text-sm leading-relaxed">
            A development harness for Claude Code. Works on any stack, runs
            entirely on your machine, MIT licensed.
          </p>
        </div>

        <div className="text-sm">
          <p className="rule-label mb-3">Project</p>
          <ul className="m-0 list-none space-y-2 p-0">
            <li>
              <a
                href={REPO_URL}
                target="_blank"
                rel="noreferrer"
                className="nav-link"
              >
                GitHub
              </a>
            </li>
            <li>
              <a
                href={`${REPO_URL}/blob/main/docs/getting-started.md`}
                target="_blank"
                rel="noreferrer"
                className="nav-link"
              >
                Getting started
              </a>
            </li>
            <li>
              <a
                href={`${REPO_URL}/blob/main/docs/commands.md`}
                target="_blank"
                rel="noreferrer"
                className="nav-link"
              >
                Command reference
              </a>
            </li>
          </ul>
        </div>

        <div className="text-sm">
          <p className="rule-label mb-3">Account</p>
          <ul className="m-0 list-none space-y-2 p-0">
            {signedIn ? (
              <li>
                <Link to="/dashboard" className="nav-link">
                  Dashboard
                </Link>
              </li>
            ) : (
              <li>
                <Link to="/signin" className="nav-link">
                  Sign in
                </Link>
              </li>
            )}
          </ul>
        </div>
      </div>

      <div className="page-wrap mt-10 flex flex-col items-start justify-between gap-3 border-t border-[var(--line)] pt-6 sm:flex-row sm:items-center">
        <p className="m-0 text-xs text-[var(--ink-dim)]">
          &copy; {year} Hyperpowers. MIT licensed.
        </p>
        <a
          href={REPO_URL}
          target="_blank"
          rel="noreferrer"
          className="text-[var(--ink-dim)] transition hover:text-[var(--ink)]"
        >
          <span className="sr-only">Hyperpowers on GitHub</span>
          <GitHubIcon size={18} />
        </a>
      </div>
    </footer>
  )
}
