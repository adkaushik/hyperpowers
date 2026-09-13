import { Link } from '@tanstack/react-router'

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
              <a href="/#pipeline" className="nav-link">
                How a run goes
              </a>
            </li>
            <li>
              <a href="/#commands" className="nav-link">
                Command reference
              </a>
            </li>
            <li>
              <a href="/#install" className="nav-link">
                Getting set up
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
      </div>
    </footer>
  )
}
